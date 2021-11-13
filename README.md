Continuous Integration process flow - github actions

INSTALLATION
Copy and paste the following snippet into your .yml file.
```
- name: Tlx Continuous Integration
  uses: jmunta-tlx/tlx-cicd@v10
  with:
    project-name: tlx-api
    project-type: mvn
    project-artifact: target/xxx.jar
    project-steps: [all] start_sonarqube create_sonarqube_project build start_sonarscan stop_sonarscan generate_sonarqube_report stop_sonarqube store_artifacts push_docker_image
```
```
/home/runner/work/_actions/jmunta-tlx/tlx-cicd/v11/ci-flow.sh all
  PROJECT=tlx-reports PROJECT_DIR=tlx-report PROJECT_TYPE=mvn ARTIFACT_PATH=target/trustlogix-report-0.0.1-SNAPSHOT.jar /home/runner/work/_actions/jmunta-tlx/tlx-cicd/v11/ci-flow.sh
```