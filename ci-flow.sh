#!/bin/bash
##########################################
# Dev CI flow
#
##########################################
WORKSPACE=$PWD
OPERATION="$@"
: ${OPERATION:="help"}
: ${DEV_MODE:="local"}
: ${USER_NAME:="jmunta-tlx"}
: ${INSTALL_MAVEN:="FALSE"}

: ${PROJECT:="tlx-api"}
: ${PROJECT_TYPE:="mvn"}
: ${ARTIFACT_PATH:="target/trustlogix-api-service-0.0.1-SNAPSHOT.jar"}
: ${SONARQUBE_USER:="admin"}
: ${SONARQUBE_PWD:="admin"}

if [ -f .docker_env_file ]; then
    source .docker_env_file
fi

export PROJECT=${PROJECT}
    
echo '  _   _   _   _   _   _   _   _   _   _  
 / \ / \ / \ / \ / \ / \ / \ / \ / \ / \ 
( t | r | u | s | t | l | o | g | i | x )
 \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ '

# Sonarqube
start_sonarqube()
{
    echo " -- start: sonarqube server --"
    echo docker-compose -f .devcontainer/docker-compose-sonarqube.yml up
    docker-compose -f .devcontainer/docker-compose-sonarqube.yml up &
    echo "Waiting for the server to come up fully..."
    bash -c 'while [[ "$(curl -s -u'"${SONARQUBE_USER}:${SONARQUBE_PWD}"' http://localhost:9000/api/system/health | jq ''.health''|xargs)" != "GREEN" ]]; do echo "Waiting for sonarqube: sleeping for 5 secs."; sleep 5; done'
    echo "Sonarqube should be up!"
}
stop_sonarqube()
{
    echo " -- stop: sonarqube server --"
    docker-compose -f .devcontainer/docker-compose-sonarqube.yml down
}

build()
{
    echo '+-+-+-+-+-+-+-+
|t|l|x|-|a|p|i|
+-+-+-+-+-+-+-+'
    docker build -f $PWD/.devcontainer/Dockerfile-dev-tools -t ${PROJECT}-dev-tools .
    echo docker run -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} --name ${PROJECT}-dev-tools ${PROJECT}-dev-tools bash -c "cd /workspaces/${PROJECT}; mvn -B clean package ${MAVEN_OPTS}"
    docker run -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 -e AWS_PROFILE=${AWS_PROFILE} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} --name ${PROJECT}-dev-tools ${PROJECT}-dev-tools bash -c "cd /workspaces/${PROJECT}; mvn -B clean package ${MAVEN_OPTS}"
}

run()
{
    echo '+-+-+-+-+-+-+-+
|t|l|x|-|a|p|i|
+-+-+-+-+-+-+-+'
    docker run -v $PWD:/workspaces/${PROJECT} -v $HOME/.m2:/root/.m2 -p 8080:8080 --name ${PROJECT}-dev-tools ${PROJECT}-dev-tools bash -c "cd /workspaces/${PROJECT}; java -jar ${ARTIFACT_PATH}"
}

# SCA: sonar scan
start_sonarscan()
{
    echo " -- start: sonar scan --"
    echo SONARQUBE_TOKEN=${SONARQUBE_TOKEN} >.docker_env_file
    echo SONAR_HOST_URL=${SONARQUBE_URL} >>.docker_env_file
    echo SONARQUBE_PWD=${SONARQUBE_PWD} >>.docker_env_file
    echo CODE_BRANCH="`git describe --all|cut -f2 -d'/'`" >>..docker_env_file

    echo docker-compose -f .devcontainer/docker-compose-sonarscanner.yml --env-file .docker_env_file up
    docker-compose -f .devcontainer/docker-compose-sonarscanner.yml --env-file .docker_env_file up
    echo "Waiting for the scan tasks to complete..."
    bash -c 'while [[ "$(curl -s -u'"${SONARQUBE_TOKEN}:"' http://localhost:9000/api/ce/activity_status|jq ''.pending+.inProgress'')" != "0" ]]; do echo "Waiting for scan tasks to complete: sleeping for 5 secs."; sleep 5; done'
    echo "Scan tasks (pending+inProgress=0) must have been completed!"
}
stop_sonarscan()
{
    echo " -- stop: sonar scan --"
    docker-compose -f .devcontainer/docker-compose-sonarscanner.yml --env-file .docker_env_file down
}
# TBD: Generate report

# Docker clean
docker_clean()
{
    echo " -- docker clean --"
    docker rm $(docker ps -aq) --force
    docker rmi $(docker images -aq) --force
    docker volume rm $(docker volume ls -q) 
}
docker_clean_containers()
{
    echo " -- docker clean containers --"
    docker rm $(docker ps -aq) --force
}
docker_clean_images()
{
    echo " -- docker clean images --"
    docker rmi $(docker images -aq) --force 
}

show_tools_local()
{
    export PATH=${PATH}:~/maven/bin
    java -version
    mvn -version
    aws --version
    git --version
}
show_tools()
{
    echo docker run ${PROJECT}-dev-tools bash -c "java --version; mvn --version; aws --version; git --version"
    docker run ${PROJECT}-dev-tools bash -c "java --version; mvn --version; aws --version; git --version"
}

help()
{
    echo "$0 <operation>"
    echo "$0  [all]|start_sonarqube|create_sonarqube_project|build|start_sonarscan|stop_sonarscan|stop_sonarqube|run|docker_clean_containers|docker_clean_images|docker_clean|show_tools_local|show_tools|generate_sonarqube_report|help"
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

# Build docker image and push to ECR
push_docker_image()
{
    # Build a docker container with image and
    # push it to ECR so that it can
    LATEST_IMAGE=$(aws ecr describe-images --repository-name tlx-engine/apiserver --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text --region us-east-2)
    if [[ $LATEST_IMAGE -eq "latest" ]]; then 
        LATEST_IMAGE=$(aws ecr describe-images --repository-name tlx-engine/apiserver --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[1]' --output text --region us-east-2) 
    fi
    if [[ $LATEST_IMAGE -ne "latest" ]]; then 
        LATEST_IMAGE=$(aws ecr describe-images --repository-name tlx-engine/apiserver --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text --region us-east-2)
    fi
    echo "#### ECR latest image version:: $LATEST_IMAGE"
    IFS='.' read -r -a array <<< "$LATEST_IMAGE"
    VERSION_CNT=$(echo "${#array[@]}")
    if [[ $VERSION_CNT -eq 3 ]];then
        LATEST_IMAGE_SUB_VERSION="${array[1]}.${array[2]}"
    fi	
    if [[ $VERSION_CNT -eq 2 ]];then	
        LATEST_IMAGE_SUB_VERSION="${array[1]}.0"
    fi
    echo "#### image subversion :: $LATEST_IMAGE_SUB_VERSION"
    NEW_IMAGE=$(echo $LATEST_IMAGE_SUB_VERSION 0.1 | awk '{print $1 + $2}')
    IMAGE_TAG="${array[0]}.$NEW_IMAGE"
    echo "#### new image tag version pushed :: $IMAGE_TAG"
    docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
    docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
    echo "::set-output name=image::$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" 
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
}

WORKDIR=$PWD
cd $WORKDIR
for TASK in `echo ${OPERATION}`
do
    ${TASK}
done


