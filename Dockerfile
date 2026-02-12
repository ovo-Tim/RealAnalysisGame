# docker build . -t real-analysis-game

# ---- Build stage ----
FROM node:20 AS builder

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

USER node

WORKDIR /home/node

COPY --chown=node:node . RealAnalysisGame

RUN git clone --depth 1 --branch main https://github.com/leanprover-community/lean4game.git

ENV ELAN_HOME=/usr/local/elan \
    PATH=/usr/local/elan/bin:$PATH \
    PORT=3000

USER root

RUN export LEAN_VERSION="$(cat RealAnalysisGame/lean-toolchain | grep -oE '[^:]+$' | sed 's/-rc[0-9]*$//')" && \
    curl --retry 3 --retry-delay 2 https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y --no-modify-path --default-toolchain $LEAN_VERSION && \
    chmod -R a+w $ELAN_HOME && \
    elan toolchain install $LEAN_VERSION && \
    elan default $LEAN_VERSION

RUN cd RealAnalysisGame && lake update -R
RUN cd RealAnalysisGame && lake exe cache get && lake build --log-level error
RUN cd /home/node/lean4game && npm i && npm run build

# ---- Runtime stage ----
FROM node:20-slim

# Lean requires libgmp at runtime
RUN apt-get update && apt-get install -y --no-install-recommends libgmp10 && \
    rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/usr/local/elan \
    PATH=/usr/local/elan/bin:$PATH \
    NODE_ENV=development

WORKDIR /home/node

# Copy Lean toolchain (needed to run lean game servers at runtime)
COPY --from=builder /usr/local/elan /usr/local/elan

# Copy lean4game package manifests and install production deps only
COPY --from=builder /home/node/lean4game/package.json /home/node/lean4game/package-lock.json /home/node/lean4game/
RUN cd /home/node/lean4game && npm ci --omit=dev && npm cache clean --force

# Copy lean4game runtime artifacts
COPY --from=builder /home/node/lean4game/relay/dist /home/node/lean4game/relay/dist
COPY --from=builder /home/node/lean4game/relay/scripts /home/node/lean4game/relay/scripts
COPY --from=builder /home/node/lean4game/client/dist /home/node/lean4game/client/dist
COPY --from=builder /home/node/lean4game/server /home/node/lean4game/server

# Copy RealAnalysisGame build artifacts (game is accessed via /#/g/local/RealAnalysisGame)
COPY --from=builder /home/node/RealAnalysisGame/.lake /home/node/RealAnalysisGame/.lake
COPY --from=builder /home/node/RealAnalysisGame/lean-toolchain /home/node/RealAnalysisGame/lean-toolchain

EXPOSE 8080
CMD ["node", "lean4game/relay/dist/src/index.js"]
