Computational Challenge PoC for EVM Execution 
=======================

This repository contains the proof-of-concept (PoC) implementation of the computational challenge for EVM on [Plasma](https://plasma.io).

This repository implements following proposal:

* [Faster Plasmabit](https://www.notion.so/ab180/Faster-Plasmabit-11011294e18b45ef88549e8152bd6bb9)
    - [x] Slashing conditions for Verifiers' dillema
    - [ ] Off-chain Interactive Game
        - [ ] Minus-Sum Incentive Curve
        - [ ] Verifiers in Race-Condition

Uses [SolEVM Enforcer](https://github.com/parsec-labs/solEVM-enforcer) by [Parsec Labs](https://github.com/parsec-labs).

## Setup
Requires [Node.js](https://nodejs.org/) ^8.0.0 and [Yarn](https://yarnpkg.com/).

```
$ yarn
```

## Project Structures

* `contracts/` : Contract sources written in Solidity. 
* `src/` : Interactive Player node implementation (Prover, Verifier, Stepper)
* `test/` : Unit tests including various attack scenarios.

## LICENSE: MIT
Copyright (C) 2018 Airbloc Pte Ltd. All rights are reserved.
