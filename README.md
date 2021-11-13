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
    project-steps: [all]
```
