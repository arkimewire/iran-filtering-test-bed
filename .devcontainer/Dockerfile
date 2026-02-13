FROM ubuntu:latest

RUN apt update && \
    echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y tshark

RUN apt install -y golang-go
RUN apt install -y build-essential
RUN apt install -y pkg-config
RUN apt install -y clang
RUN apt install -y llvm
RUN apt install -y m4
RUN apt install -y git
RUN apt install -y libelf-dev
RUN apt install -y libpcap-dev
RUN apt install -y iproute2
RUN apt install -y iputils-ping
RUN apt install -y linux-headers-generic
RUN apt install -y libbpf-dev
RUN apt install -y linux-libc-dev
RUN apt install -y cmake
RUN apt install -y libpcap-dev
RUN apt install -y libcap-ng-dev
RUN apt install -y libbfd-dev
RUN apt install -y libssl-dev
RUN ln -sf /usr/include/asm-generic/ /usr/include/asm
RUN apt install -y libcap-dev
RUN apt install -y dwarves
RUN apt install -y locales
RUN apt install -y bash-completion
RUN apt install -y cargo
RUN locale-gen en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8
RUN echo 'alias ll="ls -al"' >> ~/.bashrc
RUN echo 'if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi' >> ~/.bashrc
RUN mkdir -p ~/.local/share/bash-completion/completions
RUN echo 'docker completion bash > ~/.local/share/bash-completion/completions/docker' >> ~/.bashrc
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
RUN ~/.fzf/install --all

RUN echo 'PATH=$PATH:$HOME/.cargo/bin' >> ~/.bashrc

RUN mkdir /tools/

WORKDIR /tools/

RUN git clone --recurse-submodules https://github.com/libbpf/bpftool.git && \
    cd bpftool && \
    git checkout v7.4.0 && \
    git submodule update --init --recursive

RUN make -C bpftool/src/ install

RUN git clone --recurse-submodules https://github.com/xdp-project/xdp-tools.git

RUN make -C xdp-tools/ install

WORKDIR /

ENV GOPATH=/go
ENV PATH=$PATH:$GOPATH/bin
RUN mkdir -p $GOPATH/bin


RUN apt install -y protobuf-compiler
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# install CLAB
# containelab version will be set in devcontainer.json
# ARG _CLAB_VERSION

# Set permissions for mounts in devcontainer.json
#RUN mkdir -p /home/vscode/.vscode-server/bin
#RUN chown -R vscode:vscode /home/vscode/.vscode-server

# install some basic tools inside the container
# adjust this list based on your demands
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    sshpass \
    curl \
    iputils-ping \
    htop \
    yamllint \
    yq \
    && rm -rf /var/lib/apt/lists/* \
    && rm -Rf /usr/share/doc && rm -Rf /usr/share/man \
    && apt-get clean

# install preferred version of the containerlab
RUN bash -c "$(curl -sL https://get.containerlab.dev)"

# install Droid CLI
RUN curl -fsSL https://app.factory.ai/cli | sh
ENV PATH="/root/.local/bin:${PATH}"
RUN echo 'export PATH="/root/.local/bin:$PATH"' >> ~/.bashrc

# Install Node.js and Gemini CLI
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g @google/gemini-cli

# Install Android SDK build-tools (aapt2, apksigner) and dependencies.
# Required for building the redroid EthernetOverlay APK reproducibly.
RUN mkdir -p /usr/share/man/man1 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    openjdk-17-jdk-headless \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download Android SDK command-line tools and install build-tools + platform
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/build-tools/35.0.0:${PATH}"
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
    rm /tmp/cmdline-tools.zip && \
    yes | sdkmanager --licenses > /dev/null 2>&1 && \
    sdkmanager "build-tools;35.0.0" "platforms;android-34" && \
    rm -rf ${ANDROID_HOME}/.android
