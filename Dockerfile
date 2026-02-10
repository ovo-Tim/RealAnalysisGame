# docker build . -f RealAnalysisGame.dockerfile -t real-analysis-game
FROM node:20 AS builder

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

USER node

WORKDIR /home/node

# Copy the RealAnalysisGame files from the build context
COPY --chown=node:node . RealAnalysisGame

# Clone lean4game from bump/v4.25.2 which has PR #431 fix
# PR #431 removes gitpkg.vercel.app dependency (merged Jan 8, 2026)
RUN git clone --depth 1 --branch bump/v4.25.2 https://github.com/leanprover-community/lean4game.git

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
# We run 'lake update' because we upgraded Lean version and need to update dependencies
RUN cd /home/node/RealAnalysisGame && lake update && lake exe cache get && lake build && \
    cd /home/node/lean4game && \
    npm install --legacy-peer-deps && \
    npm run build && \
    npm cache clean --force && rm -rf ~/.cache

WORKDIR /home/node

EXPOSE 3000
CMD ["sh", "-c", "cd lean4game && npm run start"]

