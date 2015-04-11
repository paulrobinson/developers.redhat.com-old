FROM developer.redhat.com/base
MAINTAINER Jason Porter <jporter@redhat.com>

# install deps required by our build
RUN yum install -y  \
  bison \
  bzip2 \
  epel-release \
  gcc \
  gcc-c++ \
  git \
  libcurl-devel \
  libffi-devel \
  libtool \
  libxml2 \
  libxml2-devel \
  libxslt \
  libxslt-devel \
  libyaml-devel \
  openssl-devel \
  patch \
  readline-devel \
  ruby-devel \
  sqlite-devel \
  tar \
  which \ 
&& yum clean all

# Prevent encoding errors
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

RUN adduser --system --uid=1000 --home-dir /home/awestruct --shell /bin/bash -m -U awestruct

VOLUME /home/awestruct/developer.redhat.com

USER awestruct

# Add RVM keys
RUN gpg2 --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3

# Install RVM
RUN curl -L get.rvm.io | bash -s stable
RUN /bin/bash -l -c "rvm requirements && rvm autolibs enable"

# Install Ruby
COPY .ruby-version /tmp/.ruby-version
COPY .ruby-gemset /tmp/.ruby-gemset
RUN /bin/bash -l -c "rvm install $(cat /tmp/.ruby-version)"

## Build setup
# Build the current gemset (user will only need to build the difference
COPY Gemfile /tmp/Gemfile
COPY Gemfile.lock /tmp/Gemfile.lock
COPY gemrc /home/.gemrc
WORKDIR /tmp
RUN /bin/bash -l -c "bundle install"

# Add the volume for the actual project
WORKDIR /home/awestruct/developer.redhat.com 

EXPOSE 4242

ENTRYPOINT [ "/bin/bash", "-l", "-c" ]
CMD [ "rake", "clean", "preview" ]

