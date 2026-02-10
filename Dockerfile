# docker build . -f RealAnalysisGame.dockerfile -t real-analysis-game
FROM node:20 AS builder

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

USER node

WORKDIR /home/node

# Copy the RealAnalysisGame files from the build context
COPY --chown=node:node . RealAnalysisGame

# Clone lean4game from main branch which has PR #431 fix
# PR #431 removes gitpkg.vercel.app dependency (merged Jan 8, 2026)
# Using main allows us to keep v4.23.0-rc2 for compatibility
RUN git clone --depth 1 --branch main https://github.com/leanprover-community/lean4game.git

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
RUN cd /home/node/RealAnalysisGame && lake exe cache get && lake build && \
    cd /home/node/lean4game && \
    npm install --legacy-peer-deps && \
    npm run build && \
    npm cache clean --force && rm -rf ~/.cache

WORKDIR /home/node

EXPOSE 3000
CMD ["sh", "-c", "cd lean4game && npm run start"]

