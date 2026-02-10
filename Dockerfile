# docker build . -f RealAnalysisGame.dockerfile -t real-analysis-game
FROM node:20 AS builder

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# Install DNS utilities and configure DNS if needed
RUN apt-get update && apt-get install -y dnsutils && \
    rm -rf /var/lib/apt/lists/*

USER node

WORKDIR /home/node

# Copy the RealAnalysisGame files from the build context
COPY --chown=node:node . RealAnalysisGame

# Clone lean4game using the same branch as GameServer dependency in lake-manifest.json
# This ensures version compatibility between the server and client
RUN export LEAN_VERSION_FULL="$(cat /home/node/RealAnalysisGame/lean-toolchain | grep -oE '[^:]+$')" && \
    export LEAN_VERSION_BASE="$(echo $LEAN_VERSION_FULL | sed 's/-rc[0-9]*$//')" && \
    git clone --depth 1 --branch bump-$LEAN_VERSION_BASE https://github.com/leanprover-community/lean4game.git

# Clone vscode-lean4 to work around gitpkg.vercel.app 402 errors
# This dependency is normally fetched via gitpkg during npm install
RUN git clone --depth 1 https://github.com/leanprover/vscode-lean4.git /home/node/vscode-lean4 && \
    cd /home/node/vscode-lean4 && \
    git checkout 8d0cc34dcfa00da8b4a48394ba1fb3a600e3f985 || true

ENV ELAN_HOME=/usr/local/elan \
    PATH=/usr/local/elan/bin:$PATH

USER root


RUN export LEAN_VERSION="$(cat /home/node/RealAnalysisGame/lean-toolchain | grep -oE '[^:]+$')" && \
    cat /etc/resolv.conf && \
    curl --retry 3 --retry-delay 2 https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y --no-modify-path --default-toolchain $LEAN_VERSION && \
    chmod -R a+w $ELAN_HOME && \
    elan --version && \
    elan toolchain install $LEAN_VERSION && \
    elan default $LEAN_VERSION && \
    lean --version && \
    leanc --version && \
    lake --version;

# Build the Lean project and lean4game
# Note: We don't run 'lake update -R' because lake-manifest.json already locks correct dependency versions
RUN cd /home/node/RealAnalysisGame && lake exe cache get && lake build && \
    cd /home/node/lean4game && \
    sed -i 's|"lean4": "https://gitpkg.now.sh/leanprover/vscode-lean4/vscode-lean4?[^"]*"|"lean4": "file:../vscode-lean4/vscode-lean4"|g' package.json && \
    npm install --legacy-peer-deps && \
    npm run build && \
    npm cache clean --force && rm -rf ~/.cache

WORKDIR /home/node

EXPOSE 3000
CMD ["sh", "-c", "cd lean4game && npm run start"]

