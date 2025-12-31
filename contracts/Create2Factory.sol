// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CREATE2 Factory
/// @notice Deploys contracts deterministically using CREATE2 opcode
/// @dev Ensures same contract address across multiple chains
contract Create2Factory {
    /// @notice Emitted when a contract is deployed
    event ContractDeployed(address indexed deployedAddress, bytes32 indexed salt);

    /// @notice Error for failed deployment
    error DeploymentFailed();

    /// @notice Deploy a contract using CREATE2
    /// @param bytecode Creation code of contract to deploy
    /// @param salt Unique salt for address derivation
    /// @return deployedAddress Address of deployed contract
    function deploy(bytes memory bytecode, bytes32 salt) external returns (address deployedAddress) {
        // Compute deployment address
        deployedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(bytecode)
        )))));

        // Deploy using CREATE2
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x0000000000000000000000000000000000000000000000000000000000000000) // placeholder for deployed address

            // CREATE2 call: deploy(value, offset, length, salt)
            let deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

            // Check if deployment succeeded
            if iszero(deployed) {
                mstore(0x00, 0x201c6fc6) // DeploymentFailed() selector
                revert(0x00, 0x04)
            }

            mstore(ptr, deployed)
        }

        emit ContractDeployed(deployedAddress, salt);
    }

    /// @notice Deploy a contract with constructor arguments using CREATE2
    /// @param bytecode Creation code of contract to deploy
    /// @param salt Unique salt for address derivation
    /// @param constructorArgs Encoded constructor arguments
    /// @return deployedAddress Address of deployed contract
    function deployWithArgs(
        bytes memory bytecode,
        bytes32 salt,
        bytes memory constructorArgs
    ) external returns (address deployedAddress) {
        // Concatenate bytecode and constructor args
        bytes memory fullBytecode = abi.encodePacked(bytecode, constructorArgs);

        // Compute deployment address
        deployedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(fullBytecode)
        )))));

        // Deploy using CREATE2
        assembly {
            let deployed := create2(0, add(fullBytecode, 0x20), mload(fullBytecode), salt)

            if iszero(deployed) {
                mstore(0x00, 0x201c6fc6)
                revert(0x00, 0x04)
            }
        }

        emit ContractDeployed(deployedAddress, salt);
    }

    /// @notice Compute the CREATE2 address without deploying
    /// @param bytecode Creation code of contract
    /// @param salt Unique salt for address derivation
    /// @return predictedAddress Predicted deployment address
    function getAddress(bytes memory bytecode, bytes32 salt) external view returns (address predictedAddress) {
        predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(bytecode)
        )))));
    }

    /// @notice Compute the CREATE2 address with constructor args without deploying
    /// @param bytecode Creation code of contract
    /// @param salt Unique salt for address derivation
    /// @param constructorArgs Encoded constructor arguments
    /// @return predictedAddress Predicted deployment address
    function getAddressWithArgs(
        bytes memory bytecode,
        bytes32 salt,
        bytes memory constructorArgs
    ) external view returns (address predictedAddress) {
        bytes memory fullBytecode = abi.encodePacked(bytecode, constructorArgs);
        predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(fullBytecode)
        )))));
    }

    /// @notice Predict deployment addresses for multiple contracts
    /// @param bytecodes Array of creation codes
    /// @param salts Array of unique salts
    /// @return predictedAddresses Array of predicted addresses
    function getAddresses(
        bytes[] memory bytecodes,
        bytes32[] memory salts
    ) external view returns (address[] memory predictedAddresses) {
        require(bytecodes.length == salts.length, "Length mismatch");
        predictedAddresses = new address[](bytecodes.length);

        for (uint256 i = 0; i < bytecodes.length; i++) {
            predictedAddresses[i] = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff),
                address(this),
                salts[i],
                keccak256(bytecodes[i])
            )))));
        }
    }
}
