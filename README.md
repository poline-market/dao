# Poline DAO Smart Contracts

Sistema de governança descentralizada para o prediction market Poline, implementando holacracia com oráculos humanos.

## 🏗️ Arquitetura

```
┌──────────────────┐     ┌──────────────────┐
│   PolineDAO      │────▶│   CircleRegistry │
│  (Orchestrator)  │     │   (Holacracy)    │
└────────┬─────────┘     └──────────────────┘
         │
    ┌────┼────────────────────┐
    ▼    ▼                    ▼
┌────────────┐  ┌──────────────┐  ┌───────────────────┐
│PolineToken │  │StakingManager│  │  OracleVoting     │
│(Soulbound) │  │  (Lock/Slash)│  │(Event Resolution) │
└────────────┘  └──────────────┘  └─────────┬─────────┘
                                            │
                                  ┌─────────▼─────────┐
                                  │DisputeResolution  │
                                  │(Kleros-style Court│
                                  └───────────────────┘
```

## 📦 Contratos

| Contrato | Descrição |
|----------|-----------|
| `PolineToken.sol` | Token soulbound (não-transferível) com voting power e slashing |
| `CircleRegistry.sol` | Gerenciamento de círculos holacracia (Oracle, Governance, Protocol, Dispute, Community) |
| `StakingManager.sol` | Stake de tokens para se tornar oráculo com cooldown de 7 dias |
| `OracleVoting.sol` | Votação ponderada por stake para resolução de eventos YES/NO |
| `DisputeResolution.sol` | Sistema de disputas com múltiplas rodadas de escalação |
| `PolineDAO.sol` | Orquestrador principal com lifecycle de propostas |

## 🚀 Quick Start

### Pré-requisitos

- [Docker](https://www.docker.com/get-started)

### Build

```bash
cd dao
docker run --rm -v ${PWD}:/app -w /app --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "forge build"
```

### Testes

```bash
docker run --rm -v ${PWD}:/app -w /app --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "forge test -vvv"
```

### Deploy (Polygon Amoy Testnet)

```bash
# Configurar variáveis (substitua com seus valores)
PRIVATE_KEY=0x<sua_private_key>
RPC_URL=https://rpc-amoy.polygon.technology

# Deploy via Docker
docker run --rm -v ${PWD}:/app -w /app \
  --entrypoint forge ghcr.io/foundry-rs/foundry:latest \
  script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvv
```

## 🔧 Configuração

### Circles (Holacracia)

| Círculo | Escopo | Stake Mínimo |
|---------|--------|--------------|
| Oracle | Resolver eventos | 100 POLINE |
| Governance | Definir regras | 200 POLINE |
| Protocol Rules | Parâmetros AMM/fees | 150 POLINE |
| Dispute Resolution | Sistema de corte | 300 POLINE |
| Community | Crescimento | 50 POLINE |

### Parâmetros Default

| Parâmetro | Valor |
|-----------|-------|
| Unstake Cooldown | 7 dias |
| Minimum Stake (Oracle) | 100 tokens |
| Slash Percentage | 10% |
| Voting Period | 3 dias |
| Quorum | 20% |
| Dispute Escalation | 1.5x stake |

## 📁 Estrutura

```
dao/
├── foundry.toml           # Configuração Foundry (Solidity 0.8.24, Polygon)
├── contracts/
│   ├── PolineToken.sol
│   ├── CircleRegistry.sol
│   ├── StakingManager.sol
│   ├── OracleVoting.sol
│   ├── DisputeResolution.sol
│   ├── PolineDAO.sol
│   └── interfaces/        # IPolineToken, IStakingManager, etc.
├── test/
│   ├── PolineToken.t.sol
│   ├── CircleRegistry.t.sol
│   └── StakingManager.t.sol
├── script/
│   └── Deploy.s.sol       # Script de deploy completo
└── lib/
    ├── forge-std/
    └── openzeppelin-contracts/
```

## 🔐 Security Features

- **Soulbound Token**: Não-transferível, representa reputação
- **AccessControl**: Roles granulares (MINTER, SLASHER, CIRCLE_ADMIN)
- **ReentrancyGuard**: Proteção contra reentrância em todos os contratos
- **Timelock**: Delay de 1 dia antes de executar propostas
- **Slashing**: Incentivo econômico para votar corretamente

## 📖 Fluxo de Uso

### 1. Stake para ser Oráculo
```solidity
stakingManager.stake(100 ether);
// Após stake >= minimumStake, isOracle(user) = true
```

### 2. Votar em Evento
```solidity
oracleVoting.castVote(eventId, true); // YES
// ou
oracleVoting.castVote(eventId, false); // NO
```

### 3. Resolução & Slashing
```solidity
oracleVoting.resolveEvent(eventId);
// Minoria perde 10% do stake automaticamente
```

### 4. Disputa
```solidity
disputeResolution.openDispute(eventId);
// Nova rodada de votação, stake maior
```

## 📄 Licença

MIT
