pipeline {
    /*
     * The Jenkins controller coordinates the pipeline.
     * Node.js activities run inside a Node 16 Docker agent.
     */
    agent any

    options {
        // Jenkins performs an explicit checkout in the first stage.
        skipDefaultCheckout(true)

        // Prevent two builds from modifying the same Docker tags concurrently.
        disableConcurrentBuilds()

        // Retain useful logs while controlling storage consumption.
        buildDiscarder(
            logRotator(
                daysToKeepStr: '14',
                numToKeepStr: '10'
            )
        )

        // Prevent a failed external service from blocking Jenkins indefinitely.
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        IMAGE_REPOSITORY = 'masumcurtin/isec6000-assessment2-nodejs'
    }

    stages {
        stage('Checkout Source') {
            steps {
                deleteDir()
                checkout scm

                sh '''
                    echo "Checked-out commit:"
                    git rev-parse --short HEAD
                    git log -1 --pretty=format:"%h - %s"
                    echo
                '''
            }
        }

        stage('Install Dependencies') {
            agent {
                docker {
                    image 'node:16-bullseye'
                    args '-u 1000:1000 -e HOME=/tmp'
                    reuseNode true
                }
            }

            steps {
                sh '''
                    echo "Node.js build-agent versions:"
                    node --version
                    npm --version

                    npm ci --no-audit
                '''
            }
        }

        stage('Unit Tests') {
            agent {
                docker {
                    image 'node:16-bullseye'
                    args '-u 1000:1000 -e HOME=/tmp'
                    reuseNode true
                }
            }

            steps {
                sh '''
                    echo "Running automated unit tests:"
                    npm test
                '''
            }
        }

        stage('Dependency Security Scan') {
            agent {
                docker {
                    image 'node:16-bullseye'
                    args '-u 1000:1000 -e HOME=/tmp'
                    reuseNode true
                }
            }

            steps {
                script {
                    /*
                     * npm audit returns a non-zero status when findings meet
                     * the configured High/Critical failure threshold.
                     */
                    def auditStatus = sh(
                        script: '''
                            set +e

                            echo "Running dependency vulnerability scan:"
                            npm audit --audit-level=high
                            scan_status=$?

                            # Preserve a machine-readable report for Jenkins.
                            npm audit --json > npm-audit.json || true

                            exit "$scan_status"
                        ''',
                        returnStatus: true
                    )

                    if (auditStatus != 0) {
                        error(
                            'Security gate failed: High/Critical vulnerabilities ' +
                            'were detected, or the dependency scan could not complete.'
                        )
                    }

                    echo 'Security gate passed: no High/Critical dependency vulnerabilities detected.'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "Docker environment:"
                    docker version --format \
                        'Client={{.Client.Version}} Server={{.Server.Version}}'

                    echo "Building application image:"
                    docker build --pull \
                        --label "org.opencontainers.image.revision=${GIT_COMMIT}" \
                        --tag "${IMAGE_REPOSITORY}:${BUILD_NUMBER}" \
                        --tag "${IMAGE_REPOSITORY}:latest" \
                        .

                    {
                        echo "Repository=${IMAGE_REPOSITORY}"
                        echo "BuildTag=${BUILD_NUMBER}"
                        docker image inspect \
                            "${IMAGE_REPOSITORY}:${BUILD_NUMBER}" \
                            --format='ImageID={{.Id}} ConfiguredUser={{.Config.User}}'
                    } | tee docker-image-details.txt
                '''
            }
        }

        stage('Publish Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKERHUB_USER',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )
                ]) {
                    sh '''
                        # Disable command tracing before handling the token.
                        set +x
                        set -eu

                        # Always remove the temporary Docker login session.
                        trap 'docker logout >/dev/null 2>&1 || true' EXIT

                        echo "$DOCKERHUB_TOKEN" |
                            docker login \
                                --username "$DOCKERHUB_USER" \
                                --password-stdin

                        docker push "${IMAGE_REPOSITORY}:${BUILD_NUMBER}"
                        docker push "${IMAGE_REPOSITORY}:latest"

                        echo "Published ${IMAGE_REPOSITORY}:${BUILD_NUMBER}"
                        echo "Published ${IMAGE_REPOSITORY}:latest"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Publish test results and retain security/build evidence.
            junit(
                testResults: 'junit.xml',
                allowEmptyResults: true
            )

            archiveArtifacts(
                artifacts: 'junit.xml,npm-audit.json,docker-image-details.txt',
                allowEmptyArchive: true,
                fingerprint: true
            )

            // Remove local pipeline images to control DinD storage usage.
            sh '''
                docker image rm \
                    "${IMAGE_REPOSITORY}:${BUILD_NUMBER}" \
                    "${IMAGE_REPOSITORY}:latest" \
                    >/dev/null 2>&1 || true
            '''

            deleteDir()
        }

        success {
            echo 'CI/CD pipeline completed successfully.'
        }

        failure {
            echo 'CI/CD pipeline failed. Review the failed stage and archived evidence.'
        }
    }
}
