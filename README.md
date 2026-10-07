# jenkins_monitor

Monitor status of jenkins EC2 nodes

## Prerequisites

* Install [mise](https://mise.jdx.dev/getting-started.html)
* `mise install` (installs the Ruby version pinned in `mise.toml`)
* `bundle install`
* `bundle exec rake`

The Ruby version in `mise.toml` must match the `FROM ruby:<version>` tag in the `Dockerfile` (CI enforces this).

## Running

### Locally

* docker build -t jenkins-monitor .

### Update Gemfile.lock

* docker run -it --rm --name get-lock jenkins-monitor cat Gemfile.lock > Gemfile.lock
