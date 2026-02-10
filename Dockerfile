# docker build . -f RealAnalysisGame.dockerfile -t real-analysis-game
FROM node:20 AS builder

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

USER node

WORKDIR /home/node

# Copy the RealAnalysisGame files from the build context
COPY --chown=node:node . RealAnalysisGame

# Clone lean4game from bump-v4.23.0 for compatibility with v4.23.0-rc2
RUN git clone --depth 1 --branch bump-v4.23.0 https://github.com/leanprover-community/lean4game.git

# Clone required repositories locally to avoid gitpkg.vercel.app
# These would normally be fetched via gitpkg during npm install
RUN git clone --depth 1 https://github.com/leanprover/vscode-lean4.git /home/node/vscode-lean4-temp && \
    git clone --depth 1 https://github.com/hhu-adam/lean4web.git /home/node/lean4web-temp

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
# Don't run 'lake update' to preserve locked dependency versions from lake-manifest.json
RUN cd /home/node/RealAnalysisGame && lake exe cache get && lake build

RUN cd /home/node/lean4web-temp && \
    sed -i 's|"lean4-infoview":\s*"https://gitpkg[^"]*leanprover/vscode-lean4/lean4-infoview[^"]*"|"lean4-infoview": "file:../vscode-lean4-temp/lean4-infoview"|g' package.json && \
    sed -i 's|"lean4-infoview-api":\s*"https://gitpkg[^"]*leanprover/vscode-lean4/lean4-infoview-api[^"]*"|"lean4-infoview-api": "file:../vscode-lean4-temp/lean4-infoview-api"|g' package.json && \
    sed -i 's|"vscode-lean4":\s*"https://gitpkg[^"]*leanprover/vscode-lean4/vscode-lean4[^"]*"|"vscode-lean4": "file:../vscode-lean4-temp/vscode-lean4"|g' package.json && \
    cd /home/node/lean4game && \
    sed -i 's|"lean4web":\s*"git+ssh://git@github.com/hhu-adam/lean4web.git"|"lean4web": "file:../lean4web-temp"|g' package.json

RUN cd /home/node/lean4game && cat package.json
RUN cd /home/node/lean4web-temp && cat package.json

RUN npm install --legacy-peer-deps && \
    npm run build && \
    npm cache clean --force && rm -rf ~/.cache

WORKDIR /home/node

EXPOSE 3000
CMD ["sh", "-c", "cd lean4game && npm run start"]
