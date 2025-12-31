// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

/// @title Salt Generator Helper
/// @notice Helps generate and validate CREATE2 deployment salts
/// @dev
/// Usage:
///   forge script script/GenerateSalt.s.sol --sig "generateSalt(string)" \
///     --rpc-url http://localhost:8545 \
///     -vvv
///
///   forge script script/GenerateSalt.s.sol --sig "generateRandomSalt()" \
///     --rpc-url http://localhost:8545 \
///     -vvv
contract GenerateSalt is Script {
    /// @notice Generate salt from string (for descriptive deployment names)
    /// @param input String to convert to bytes32 salt
    function generateSalt(string memory input) external view {
        bytes32 salt = keccak256(abi.encodePacked(input));

        console.log("\n=== SALT GENERATION RESULT ===");
        console.log("Input string:");
        console.log(input);
        console.log("\nGenerated salt (bytes32):");
        console.logBytes32(salt);
        console.log("\nAs hex string:");
        console.log(toHexString(salt));
        console.log("==============================\n");

        console.log("[INFO] Use this salt in your .env file:");
        console.log(string(abi.encodePacked("SALT=", toHexString(salt))));
        console.log("");
    }

    /// @notice Generate random salt (for production deployments)
    function generateRandomSalt() external view {
        bytes32 salt;
        assembly {
            // Use block timestamp and prevrandao as entropy source
            // Note: For better randomness, use this in different blocks
            let ptr := mload(0x40)
            mstore(ptr, timestamp())
            mstore(add(ptr, 32), prevrandao())
            salt := keccak256(ptr, 64)
        }

        console.log("\n=== RANDOM SALT GENERATED ===");
        console.log("Generated salt (bytes32):");
        console.logBytes32(salt);
        console.log("\nAs hex string:");
        console.log(toHexString(salt));
        console.log("=============================\n");

        console.log("[INFO] Use this salt in your .env file:");
        console.log(string(abi.encodePacked("SALT=", toHexString(salt))));
        console.log("");
        console.log("[WARNING] Save this salt! If you lose it, you cannot redeploy to the same address.");
        console.log("");
    }

    /// @notice Validate that a salt is properly formatted bytes32
    /// @param saltBytes Salt as bytes (can be hex string or bytes32)
    function validateSalt(bytes memory saltBytes) external pure {
        require(saltBytes.length == 32, "Salt must be 32 bytes");

        bytes32 salt;
        assembly {
            salt := mload(add(saltBytes, 32))
        }

        console.log("\n=== SALT VALIDATION ===");
        console.log("Salt is valid 32 bytes:");
        console.logBytes32(salt);
        console.log("=======================\n");
    }

    /// @notice Compute CREATE2 address for a contract (without deploying)
    /// @param factoryAddress CREATE2 factory address
    /// @param deploymentSalt Deployment salt
    /// @param bytecode Contract bytecode (as hex string)
    function computeCreate2Address(
        address factoryAddress,
        bytes32 deploymentSalt,
        string memory bytecode
    ) external view {
        bytes memory bytecodeBytes = vm.parseBytes(bytecode);

        address predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            factoryAddress,
            deploymentSalt,
            keccak256(bytecodeBytes)
        )))));

        console.log("\n=== CREATE2 ADDRESS PREDICTION ===");
        console.log("Factory address:");
        console.logAddress(factoryAddress);
        console.log("\nDeployment salt:");
        console.logBytes32(deploymentSalt);
        console.log("\nPredicted contract address:");
        console.logAddress(predictedAddress);
        console.log("==================================\n");
    }

    /// @notice Compare multiple salts to see which produce different addresses
    /// @param salts Array of salts to compare
    function compareSalts(bytes32[] memory salts) external view {
        console.log("\n=== SALT COMPARISON ===");
        console.log("Comparing", salts.length, "salts...\n");

        for (uint256 i = 0; i < salts.length; i++) {
            console.log("Salt", i+1, ":");
            console.logBytes32(salts[i]);
            console.log("Hex:", toHexString(salts[i]));
            console.log("");
        }
        console.log("========================\n");
    }

    /// @notice Convert address to hex string with 0x prefix
    function toHexString(address addr) internal pure returns (string memory) {
        return string(abi.encodePacked("0x", _toHex(uint160(addr))));
    }

    /// @notice Convert bytes32 to hex string with 0x prefix
    function toHexString(bytes32 value) internal pure returns (string memory) {
        return string(abi.encodePacked("0x", _toHexBytes32(value)));
    }

    function _toHex(uint160 value) internal pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(40);

        for (uint256 i = 0; i < 20; i++) {
            uint256 byteValue = (value >> (152 - 8 * i)) & 0xff;
            result[i * 2] = alphabet[byteValue >> 4];
            result[i * 2 + 1] = alphabet[byteValue & 0x0f];
        }

        return result;
    }

    function _toHexBytes32(bytes32 value) internal pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(64);

        for (uint256 i = 0; i < 32; i++) {
            uint256 byteValue = uint8(value[i]);
            result[i * 2] = alphabet[byteValue >> 4];
            result[i * 2 + 1] = alphabet[byteValue & 0x0f];
        }

        return result;
    }
}
