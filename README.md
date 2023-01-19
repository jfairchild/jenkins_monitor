# jenkins_monitor

Monitor status of jenkins EC2 nodes

## Running

### Locally

* docker build -t jenkins-monitor .

### Update Gemfile.lock

* docker run -it --rm --name get-lock jenkins-monitor cat Gemfile.lock > Gemfile.lock
