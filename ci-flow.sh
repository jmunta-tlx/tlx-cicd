#!/bin/bash -x
##########################################
# Dev CI flow
#
##########################################
WORKSPACE=$PWD
OPERATION="$@"
SCRIPT_DIR=$( cd `dirname $0`; pwd )
: ${OPERATION:="help"}
: ${DEV_MODE:="local"}
: ${USER_NAME:="jmunta-tlx"}
: ${INSTALL_MAVEN:="FALSE"}

: ${PROJECT:="tlx-api"}
: ${PROJECT_DIR:="."}
: ${PROJECT_PACKAGE_DIR:="."}
: ${PROJECT_TYPE:="mvn"}
: ${PROJECT_BRANCH:="develop"}
: ${BUILD_COMMAND:="mvn -B clean package"}
: ${ARTIFACT_PATH:="target/trustlogix-api-service-0.0.1-SNAPSHOT.jar"}
: ${ARTIFACT_NAME:="trustlogix-api-service"}
: ${PUBLISH_DOCKER_BUILD_ARGS:="--build-arg AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} --build-arg AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"}
: ${SONARQUBE_USER:="admin"}
: ${SONARQUBE_PWD:="admin"}
: ${RETRY_COUNT:=2}
: ${GIT_USER_NAME:="jmunta-tlx"}
: ${GIT_USER_EMAIL:="jmunta@trustlogix.io"}
: ${PROJECT_ROOT_ACCOUNT:="trustlogix"}


if [ -f .docker_env_file ]; then
    source .docker_env_file
fi

export PROJECT=${PROJECT}

    
echo '  _   _   _   _   _   _   _   _   _   _  
 / \ / \ / \ / \ / \ / \ / \ / \ / \ / \ 
( t | r | u | s | t | l | o | g | i | x )
 \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ '

# Prepare project type
prepare_project()
{
    cp -r ${SCRIPT_DIR}/project_${PROJECT_TYPE}/Dockerfile-dev-tools ${SCRIPT_DIR}/.devcontainer/
    if [ ! -f sonar-project.properties ]; then
        sed -e "s/{{SONAR_PROJECT}}/${PROJECT}/g" \
            ${SCRIPT_DIR}/project_${PROJECT_TYPE}/sonar-project.properties >${PWD}/sonar-project.properties
    fi
}

# Sonarqube
start_sonarqube()
{
    echo " -- start: sonarqube server --"
    echo docker-compose -f ${SCRIPT_DIR}/.devcontainer/docker-compose-sonarqube.yml up
    docker compose -f ${SCRIPT_DIR}/.devcontainer/docker-compose-sonarqube.yml up &
    echo "Waiting for the server to come up fully..."
    bash -c 'while [[ "$(curl -s -u'"${SONARQUBE_USER}:${SONARQUBE_PWD}"' http://localhost:9000/api/system/health | jq ''.health''|xargs)" != "GREEN" ]]; do echo "Waiting for sonarqube: sleeping for 5 secs."; sleep 5; done'
    echo "Sonarqube should be up!"
}
stop_sonarqube()
{
    echo " -- stop: sonarqube server --"
    docker-compose -f ${SCRIPT_DIR}/.devcontainer/docker-compose-sonarqube.yml down
}

build()
{
    build_${PROJECT_TYPE}
}

build_mvn()
{
    echo '+-+-+-+-+-+-+-+
|t|l|x|-|m|v|n|
+-+-+-+-+-+-+-+'
    docker build -f ${SCRIPT_DIR}/.devcontainer/Dockerfile-dev-tools -t ${PROJECT}-dev-tools .
    echo docker run --rm -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 \
        -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
        --name ${PROJECT}-dev-tools ${PROJECT}-dev-tools \
        bash -c "cd /workspaces/${PROJECT}/${PROJECT_DIR}; ${BUILD_COMMAND} ${MAVEN_OPTS}"
    docker run --rm -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 \
        -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
        --name ${PROJECT}-dev-tools ${PROJECT}-dev-tools \
        bash -c "cd /workspaces/${PROJECT}/${PROJECT_DIR}; ${BUILD_COMMAND} ${MAVEN_OPTS}" 2>&1 | tee docker_run_build_log.txt
    if [ -f docker_run_build_log.txt ]; then
        FAILURES="`grep 'BUILD FAILURE' docker_run_build_log.txt`"
        if [ "${FAILURES}" != "" ]; then
            echo "Build failed. exiting..."
            exit 1
        fi
    fi
}

#yarn install && CI=false yarn build
build_yarn()
{
    echo '+-+-+-+-+-+-+-+
|t|l|x|-|y|a|r|n|
+-+-+-+-+-+-+-+'
    #docker build -f ${SCRIPT_DIR}/.devcontainer/Dockerfile-dev-tools -t ${PROJECT}-dev-tools .
    echo docker run --rm -v $PWD:/workspaces/${PROJECT} -p 8080:8080 \
        -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
        --name ${PROJECT}-dev-tools biswalaws/dev-tools \
        bash -c "cd /workspaces/${PROJECT}/${PROJECT_DIR}; yarn install && CI=false yarn build"
    docker run --rm -v $PWD:/workspaces/${PROJECT} -p 8080:8080 \
        -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
        --name ${PROJECT}-dev-tools biswalaws/dev-tools \
        bash -c "cd /workspaces/${PROJECT}/${PROJECT_DIR}; yarn install && CI=false yarn build"
    
    yarn_test_run
}

# Run tests
yarn_test_run()
{
    docker run --rm -v $PWD:/workspaces/${PROJECT} -p 8080:8080 \
        -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
        --name ${PROJECT}-dev-tools biswalaws/dev-tools \
        bash -c "cd /workspaces/${PROJECT}/${PROJECT_DIR};chmod a+x runTests.sh;./runTests.sh"
}

run()
{
    echo '+-+-+-+-+-+-+-+
|t|l|x|-|m|v|n|
+-+-+-+-+-+-+-+'
    docker run -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 \
        --name ${PROJECT}-dev-tools ${PROJECT}-dev-tools bash -c "cd /workspaces/${PROJECT}/${PROJECT_DIR}; java -jar ${ARTIFACT_PATH}"
}

# SCA: sonar scan
start_sonarscan()
{
    echo " -- start: sonar scan --"
    echo SONARQUBE_TOKEN=${SONARQUBE_TOKEN} >.docker_env_file
    echo SONAR_HOST_URL=${SONARQUBE_URL} >>.docker_env_file
    echo SONARQUBE_PWD=${SONARQUBE_PWD} >>.docker_env_file
    echo CODE_BRANCH="`git describe --all|cut -f2 -d'/'`" >>..docker_env_file

    echo docker-compose -f ${SCRIPT_DIR}/.devcontainer/docker-compose-sonarscanner.yml --env-file .docker_env_file up
    docker compose -f ${SCRIPT_DIR}/.devcontainer/docker-compose-sonarscanner.yml --env-file .docker_env_file up
    echo "Waiting for the scan tasks to complete..."
    bash -c 'while [[ "$(curl -s -u'"${SONARQUBE_TOKEN}:"' http://localhost:9000/api/ce/activity_status|jq ''.pending+.inProgress'')" != "0" ]]; do echo "Waiting for scan tasks to complete: sleeping for 5 secs."; sleep 5; done'
    echo "Scan tasks (pending+inProgress=0) must have been completed!"
}
stop_sonarscan()
{
    echo " -- stop: sonar scan --"
    docker compose -f ${SCRIPT_DIR}/.devcontainer/docker-compose-sonarscanner.yml --env-file .docker_env_file down
}
# TBD: Generate report

# Docker clean
docker_clean()
{
    echo " -- docker clean --"
    docker_clean_containers
    docker_clean_volumes
    #docker_clean_images
}
docker_clean_containers()
{
    echo " -- docker clean containers --"
    #docker rm $(docker ps -aq) --force || true
    docker rm biswalaws/dev-tools sonarqube sonarqube_pg  --force || true
}
#docker_clean_images()
{
    echo " -- docker clean images --"
    docker rmi $(docker images -aq) --force || true
}

docker_clean_volumes()
{
    #docker volume rm $(docker volume ls -q) || true
    docker volume rm devcontainer_pg_data devcontainer_pg_db || true
}

show_tools()
{
    show_tools_${PROJECT_TYPE}
}

show_tools_mvn()
{
    echo docker run --rm ${PROJECT}-dev-tools bash -c "java --version; mvn --version; aws --version; git --version"
    docker run --rm biswalaws/dev-tools bash -c "java --version; mvn --version; aws --version; git --version"
}

show_tools_yarn()
{
    echo docker run --rm biswalaws/dev-tools bash -c "git --version; node --version; yarn --version"
    docker run --rm biswalaws/dev-tools bash -c "git --version; node --version; yarn --version"
}


help()
{
    echo "$0 <operation>"
    echo "$0  [all]|start_sonarqube|create_sonarqube_project|build|start_sonarscan|stop_sonarscan|stop_sonarqube|run|docker_clean_containers|docker_clean_images|docker_clean|show_tools|generate_sonarqube_report|help"
    echo "Exmaples: $0 build"
}
generate_sonarqube_token()
{
    SONARQUBE_TOKEN=`curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "name=${PROJECT}_$$" -u ${SONARQUBE_USER}:${SONARQUBE_PWD} http://localhost:9000/api/user_tokens/generate |jq '.token'|xargs`
    export SONARQUBE_TOKEN=${SONARQUBE_TOKEN}
    echo SONARQUBE_TOKEN=${SONARQUBE_TOKEN} >.docker_env_file
}
revoke_sonarqube_token()
{
    SONARQUBE_TOKEN=`curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "name=${PROJECT}" -u ${SONARQUBE_USER}:${SONARQUBE_PWD} http://localhost:9000/api/user_tokens/revoke`
}

create_sonarqube_project()
{
    curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "name=${PROJECT}&project=${PROJECT}" -u ${SONARQUBE_USER}:${SONARQUBE_PWD} http://localhost:9000/api/projects/create
    generate_sonarqube_token
}
delete_sonarqube_project()
{
    curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "name=${PROJECT}&project=${PROJECT}" -u ${SONARQUBE_USER}:${SONARQUBE_PWD} http://localhost:9000/api/projects/delete
    revoke_sonarqube_token
}

generate_sonarqube_report()
{
    METRICS="alert_status,bugs,vulnerabilities,security_rating,coverage,code_smells,duplicated_lines_density,ncloc,sqale_rating,reliability_rating,sqale_index"
    OUTPUT=sonarqube_report.html
    echo "<html><head><title>Sonarqube report for ${PROJECT}</title></head><body><h1>${PROJECT}</h1>" >${OUTPUT}
    echo "<table>" >>${OUTPUT}
    for METRIC in `echo ${METRICS}|sed 's/,/ /g'`
    do
        echo "<td>" >>${OUTPUT}
        curl -s -u "${SONARQUBE_TOKEN}:" "http://localhost:9000/api/project_badges/measure?project=${PROJECT}&metric=${METRIC}" >>${OUTPUT}
        echo "</td>" >>${OUTPUT}
    done
    echo "</table></body></html>" >>${OUTPUT}
    echo "Report at $PWD/${OUTPUT}"
    if [ "${REPORT_NOTIFY}" != "" ]; then
        SLACK_CHANNEL="`echo ${REPORT_NOTIFY}|cut -f2 -d'#'`"
        UNIT_TEXT=`cat target/site/surefire-report.html| sed -n '/name="Summary"/, /name="Package_List"/p'|egrep '<td>'|cut -f2 -d'>'|cut -f1 -d'<'|xargs`
        SONAR_TEXT="`cat ${OUTPUT} |egrep 'fill-opacity' |cut -f2 -d'<'|cut -f2 -d'>'|xargs`"
        SLACK_TEXT="\n. Unit testing (Total Errors Failures Skipped Success Time): ${UNIT_TEXT} \n. Sonarqube SCA+Codecoverage: ${SONAR_TEXT}"
        curl -X POST --data-urlencode "payload={\"channel\":\"#${SLACK_CHANNEL}\", \"attachments\":[{\"title\":\"${SLACK_TITLE}\", \"text\":\"${SLACK_TEXT}\"}]}" ${SLACK_WEBHOOK}   
    fi
}

# Save the generated artifacts
store_artifacts()
{
    if [ "${ARTIFACTS_LOCATION}" == "s3://*" ]; then
        echo "Storing artifacts to S3 at ${ARTIFACTS_LOCATION}"
        AWS_PROFILE=${AWS_PROFILE} AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
            aws s3 cp /workspaces/${PROJECT}/${ARTIFACT_PATH} ${ARTIFACTS_LOCATION}/
    else 
        echo "WARNING: Not storing artifacts: "
        echo "   /workspaces/${PROJECT}/${ARTIFACT_PATH}"
    fi
}

prepare_release()
{
    OUT_SEMANTIC_RELEASE=/tmp/semantic_release_log.txt
    docker run --rm -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 \
        -e GITHUB_TOKEN=${GITHUB_TOKEN} \
        -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
        -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} --name ${PROJECT}-dev-tools \
        biswalaws/dev-tools bash -c "cd /workspaces/${PROJECT}/${PROJECT_PACKAGE_DIR}; ls -lrt; git config --global --add safe.directory /workspaces/${PROJECT}; git remote -v; npx semantic-release" 2> ${OUT_SEMANTIC_RELEASE}
    
    if [ -f ${OUT_SEMANTIC_RELEASE} ]; then
        cat ${OUT_SEMANTIC_RELEASE}
        OUT_OF_VERSION="`egrep '^Based.*within the range' ${OUT_SEMANTIC_RELEASE} |grep -oh '>=[0-9]\+\.[0-9]\+\.[0-9]\+ <'|cut -f2 -d'='`"
        if [ ! "${OUT_OF_VERSION}" = "" ]; then
            OUT_OF_VERSION="`egrep ': The release .* on branch .* cannot be published as it is out of range' ${OUT_SEMANTIC_RELEASE} |grep -oh '[0-9]\+\.[0-9]\+\.[0-9]\+'`"            
        else
            OUT_OF_VERSION="`egrep '^Based.*within the range' ${OUT_SEMANTIC_RELEASE} |grep -oh '>=[0-9]\+\.[0-9]\+\.[0-9]\+'|cut -f2 -d'='`"
        fi
        if [ ! "${OUT_OF_VERSION}" = "" ]; then
          echo "Getting the latest tag..."
          OUT_OF_VERSION="`git tag | sort -V | tail -1 |sed 's/v//g'`"
          PATCH_VERSION="`echo ${OUT_OF_VERSION}|cut -f3 -d'.'`"
          NEW_PATCH_VERSION=`expr ${PATCH_VERSION} + 1`
          NEW_TAG_VERSION="`echo ${OUT_OF_VERSION}|cut -f1-2 -d'.'`.${NEW_PATCH_VERSION}"
          pwd
          echo $USER
          sudo chmod -R 777 .git
          git branch
          git config --global hub.protocol https
          git remote set-url origin https://${GITHUB_TOKEN}:x-oauth-basic@github.com/${PROJECT_ROOT_ACCOUNT}/${PROJECT}.git
          git config --global user.name ${GIT_USER_NAME}
          git config --global user.email ${GIT_USER_EMAIL}
          git checkout ${PROJECT_BRANCH}
          git tag -a v${NEW_TAG_VERSION} -m "Leveling version ${NEW_TAG_VERSION}"
          git push origin v${NEW_TAG_VERSION}
          cat ${OUT_SEMANTIC_RELEASE} |sed -n '/following commits are responsible for the invalid release/,/Those commits should be moved to a valid branch/p;/Those commits should be moved to a valid branch/q' \
                | egrep -v 'following commits are responsible for the invalid release'|egrep -v 'Those commits should be moved to a valid branch' > /tmp/new_commits.txt
          
          if [ -f /tmp/new_commits.txt ]; then
            NEW_CHANGE_LOG=/tmp/new_changelog.md
            echo "## [v${NEW_TAG_VERSION}] (`date +'%Y-%m-%d'`)" >${NEW_CHANGE_LOG}
            cat /tmp/new_commits.txt >>${NEW_CHANGE_LOG}
            cat CHANGELOG.md >> ${NEW_CHANGE_LOG}
            cp ${NEW_CHANGE_LOG} CHANGELOG.md
            cat CHANGELOG.md
            git checkout ${PROJECT_BRANCH}
            git add CHANGELOG.md
            git commit -m "fix: v${NEW_TAG_VERSION} commits" CHANGELOG.md
            git push origin ${PROJECT_BRANCH}
          else
            echo "No commits found for changelog update."
          fi
          RETRY_COUNT=`expr $RETRY_COUNT - 1 `
          if [ $RETRY_COUNT -gt 0 ]; then
            prepare_release
          fi
        fi
    fi
    if [ ! -f new_release_version.txt ]; then
        echo "WARNING: No new release as release version file is not found! "
        return
    fi
    IMAGE_TAG="`cat new_release_version.txt|cut -f2 -d=`"
    echo "IMAGE_TAG=${IMAGE_TAG}"
    CUR_DIR=`pwd`
    echo "CUR_DIR=$CUR_DIR"
    cd ${PROJECT_DIR}
    echo `pwd; ls`
    cd target && JAR_NAME="`ls *.jar`" && cd ..
    echo "#### new image tag version pushed :: ${IMAGE_TAG}"
    sed -i "s/${ARTIFACT_NAME}-.*.jar/${JAR_NAME}/g" Dockerfile
    echo docker build ${PUBLISH_DOCKER_BUILD_ARGS} -t $ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG} .
    docker build ${PUBLISH_DOCKER_BUILD_ARGS} -t $ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG} .
    echo docker push $ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG}
    docker push $ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG}
    echo docker tag $ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG} $ECR_REGISTRY/$ECR_REPOSITORY:latest
    docker tag $ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG} $ECR_REGISTRY/$ECR_REPOSITORY:latest
    echo docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
    docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
    echo "::set-output name=docker-image::$ECR_REGISTRY/$ECR_REPOSITORY:${IMAGE_TAG}"
    echo "::set-output name=artifact-location::${JAR_NAME}"
    echo "::set-output name=image-tag::${IMAGE_TAG}"
    cd $CUR_DIR
    
}

# All operations
all()
{
    start_sonarqube
    create_sonarqube_project
    build
    start_sonarscan
    stop_sonarscan
    generate_sonarqube_report
    stop_sonarqube
    prepare_release
}

WORKDIR=$PWD
cd $WORKDIR
prepare_project
for TASK in `echo ${OPERATION}`
do
    ${TASK}
done


