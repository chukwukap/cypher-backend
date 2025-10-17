// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Cypher} from "../src/Cypher.sol";

// anvil
//  export RPC_URL="127.0.0.1:8545" && export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" && export USDC_TOKEN="0x036cbd53842c5426634e7929541ec2318f3dcf7e"

// forge script script/DeployCypher.s.sol:DeployCypher --via-ir --optimize --optimizer-runs 200 --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv

contract DeployCypher is Script {
    function run() external returns (Cypher deployed) {
        // Read required environment variables.
        address usdc = vm.envAddress("USDC_TOKEN");

        vm.startBroadcast();
        deployed = new Cypher(usdc);
        vm.stopBroadcast();

        console2.log("Cypher deployed at:", address(deployed));
        console2.log("USDC token:", usdc);
    }
}
