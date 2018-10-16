pragma solidity ^0.4.24;
pragma experimental "v0.5.0";
pragma experimental ABIEncoderV2;

import { EVMStack } from "solevm-truffle/EVMStack.slb";
import { EVMAccounts } from "solevm-truffle/EVMAccounts.slb";
import { EthereumRuntime } from "./EthereumRuntime.sol";

contract OffchainEthereumRuntime is EthereumRuntime {

    /**
     * @dev Execute a bytecode on off-chain.
     * DO NOT run this function on onchain - it is supposed to run a step on offchain,
     * and it has no gas optimization nor security considerations. :P
     */
    function executeStep(
        EthereumRuntime.TxInput memory input, 
        EthereumRuntime.TxInfo memory info,
        EthereumRuntime.ExecutionContext memory context
    )
        public
        pure
        returns (
            EthereumRuntime.Result memory result,
            EthereumRuntime.ExecutionContext memory postContext,
            bytes32 memory postStateRoot
        )
    {
        EthereumRuntime.EVMInput memory evmInput;
        evmInput.context = info;
        evmInput.handlers = _newHandlers();

        evmInput.caller = input.from;
        evmInput.target = input.to;
        evmInput.value = input.value;
        evmInput.data = input.data;
        evmInput.staticExec = input.staticExec;

        evmInput.pcStart = context.pc;
        evmInput.pcEnd = context.pc + 1;
        evmInput.gas = context.gasRemaining;
        evmInput.mem = EVMMemory.fromArray(context.mem);
        evmInput.stack = EVMStack.fromArray(context.stack);
        evmInput.accounts = _accsFromArray(context.accounts, context.accountsCode);

        EVM memory evm = super._call(evmInput, input.staticExec ? CallType.StaticCall : CallType.Call);
        
        result.errno = evm.errno;
        result.returnData = evm.returnData;

        postContext.pc = evm.pc;
        postContext.gasRemaining = evm.gas;
        postContext.stack = evm.stack.toArray();
        postContext.mem = evm.mem.toArray();
        (postContext.accounts, postContext.accountsCode) = evm.accounts.toArray();

        postStateRoot = calculateStateRoot(evm);
    }
}
