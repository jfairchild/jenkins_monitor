FROM ruby:3.2
ENV GEM_HOME="/usr/local/bundle"
ENV PATH $GEM_HOME/bin:$GEM_HOME/gems/bin:$PATH

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY scripts ./scripts/
COPY login.yml /root/.jenkins_api_client/login.yml

CMD bundle exec ruby ./scripts/jenkins_monitor.rb
