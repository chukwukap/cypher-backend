// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Cypher} from "../src/Cypher.sol";

/// @notice Simple seeder for KOL hashes. Edit `hashes` and run.
contract SeedKOLs is Script {
    function run() external {
        address cypher = vm.envAddress("CYPHER_ADDRESS");
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // EDIT THIS LIST: paste your bytes32 hashes here.
        bytes32[] memory hashes = new bytes32[](15);
        hashes[
            0
        ] = 0x54ee7dc2425581581c47469e5eb1f5eed4233fcbddf6c7592f1580aa348c89b4;
        hashes[
            1
        ] = 0xfa4dffc9e824f830cf7d07fc7765ba1d7b344d923dd9083258189156f4932796;
        hashes[
            2
        ] = 0x33fd3a1a2f6025be5b2d3026fea143df162bb647c138b6d16851023d3c6518a7;
        hashes[
            3
        ] = 0x4577b1186726aefd500341efa18943241fb9994e2e412da5cc558d28c6e52ddf;
        hashes[
            4
        ] = 0xcb43db8e11342c57139c6028ef0ca9ff0606bfa1218225ea9a0ccb7e42206362;
        hashes[
            5
        ] = 0x673c01c3285d988aa04a27f5a542a4a304005c687956087d40ac2df25856dcdb;
        hashes[
            6
        ] = 0x0524cdf42f7e19c1b50b880d9d343bed05b80f21f29ecec6cff29e9657177853;
        hashes[
            7
        ] = 0x48c5a7987a74c243ccde734e1679bd0ec85b03ad4b0d329815fa18a928bed2ca;
        hashes[
            8
        ] = 0xf62eed8c614d9af05170cfd5366e70ce2b5b581277ed9bda90ee06ec1c0ac70b;
        hashes[
            9
        ] = 0x1607be6baa59b952f720dc10f894f0fb97723aa12c72c2f925dfbd8f301ea770;
        hashes[
            10
        ] = 0xc6efb078ba9e17a714af044d45caa889df54c72db5a8f519a48117964c45e811;
        hashes[
            11
        ] = 0xbcf86f88c85a4d7c8956da3d72aa06352a87f16a97cd2c9897a07492f92a6ad2;
        hashes[
            12
        ] = 0x6dc2f619db0779da93991f96b7d19da693074782b6575cd6617f98bb4ff77bdc;
        hashes[
            13
        ] = 0x89a423337cdbf4041d1f104772e9b3b58f5c0141b08227b35aab83cab7e0e1ed;
        hashes[
            14
        ] = 0xdbbb309b2d1e68f542ca8002db4910bef497c5ad9e7e7c1168159960dd05d2e7;

        require(hashes.length > 0, "SeedKOLs: no hashes set");

        vm.startBroadcast(pk);
        // Clear existing KOL hashes before seeding new ones.
        Cypher(cypher).clearKOLs();
        console2.log("Cleared existing KOL hashes on", cypher);
        for (uint256 i = 0; i < hashes.length; i++) {
            Cypher(cypher).addKOL(hashes[i]);
            console2.logBytes32(hashes[i]);
        }
        vm.stopBroadcast();
    }
}
