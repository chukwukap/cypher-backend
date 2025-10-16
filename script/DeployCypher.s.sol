// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Cypher} from "../src/Cypher.sol";

/// @notice Simple deployer for the Cypher contract.
/// Usage examples:
///  - forge script script/DeployCypher.s.sol:DeployCypher \
///      --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
///      --broadcast --verify --verifier blockscout \
///      --etherscan-api-key $VERIFIER_KEY \
///      -vvvv
///  - Ensure USDC token address is provided via env: USDC_TOKEN=0x...
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
