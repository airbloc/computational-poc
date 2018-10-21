Computational Challenge PoC for EVM Execution 
=======================

This repository contains the proof-of-concept (PoC) implementation of the computational challenge for EVM on [Plasma](https://plasma.io).

This repository implements following proposal:

* [More Viable Plasmabit](https://www.notion.so/ab180/More-Viable-Plasmabit-11011294e18b45ef88549e8152bd6bb9)
    * Slashing conditions for Verifiers' dillema
    * Off-chain Interactive Game

Uses [SolEVM Enforcer](https://github.com/parsec-labs/solEVM-enforcer) by [Parsec Labs](https://github.com/parsec-labs).

## Setup

```
yarn
```

## Project Structures

* `contracts/` : Contract sources written in Solidity. 
* `src/` : Interactive Player node implementation (Prover, Verifier, Stepper)
* `test/` : Unit tests including various attack scenarios.


## LICENSE: MIT
Copyright (C) 2018 Airbloc Pte Ltd. All rights are reserved.
