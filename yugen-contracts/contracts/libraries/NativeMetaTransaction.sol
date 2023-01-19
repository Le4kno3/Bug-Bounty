// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import "./EIP712Base.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract NativeMetaTransaction is EIP712Base {
    using SafeMath for uint256;

    bytes32 private constant META_TRANSACTION_TYPEHASH =
        keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionSignature)"));
    event MetaTransactionExecuted(
        address userAddress,
        address payable relayerAddress,
        bytes functionSignature
    );

    mapping(address => uint256) nonces;

    /*
     * Meta transaction structure.
     * No point of including value field here as if user is doing value transfer then he has the funds to pay for gas
     * He should call the desired function directly in that case.
     */
    struct MetaTransaction {
        uint256 nonce;
        address from;
        bytes functionSignature;
    }

    /*
     * @param userAddress - This is the address of the user for whom we are executing the meta transaction.
     * @param msg.sender - The person who is executing the meta transaction.
     * @param functionSignature - Is the function that the `userAddress` wishes to execute using meta transaction.
     * @param R S V - message signatures
     *
     * @notice - This function will be inherited to contracts where there are function which are required to run as meta transactions.
     * @notice - message that is hashed = "\x19\x01", getDomainSeperator(), messageHash
     *
     * @audit-ok - This is a public function with almost no checks on identity,
     * Can any arbitrary user sign a function signature for a function of a contract that inherits this (NativeMetaTransaction) contract?
     * yes he can sign only his or some random user, it cannot impersontate other users, as it does not know its private key.
     * As a standard practice of EIP this function is public.
     */
    function executeMetaTransaction(
        address userAddress,
        bytes memory functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) public payable returns (bytes memory) {
        //get details which has to run via meta transaction fashion.
        MetaTransaction memory metaTx = MetaTransaction({
            nonce: nonces[userAddress],
            from: userAddress,
            functionSignature: functionSignature
        });

        //verify if the userAddress (on behalf of which this meta transation will be run) is indeed the user who he say he is.
        require(verify(userAddress, metaTx, sigR, sigS, sigV), "Signer and signature do not match");

        // increase nonce for user (to avoid re-use)
        nonces[userAddress] = nonces[userAddress].add(1);

        emit MetaTransactionExecuted(userAddress, msg.sender, functionSignature);

        // Append userAddress and relayer address at the end to extract it from calling context
        // @audit - where is relayer address. Also does this function assumes that is created for a particular function call.
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodePacked(functionSignature, userAddress)
        );
        require(success, "Function call not successful");

        return returnData;
    }

    function hashMetaTransaction(MetaTransaction memory metaTx) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    META_TRANSACTION_TYPEHASH,
                    metaTx.nonce,
                    metaTx.from,
                    keccak256(metaTx.functionSignature)
                )
            );
    }

    function getNonce(address user) public view returns (uint256 nonce) {
        nonce = nonces[user];
    }

    /*
     * @param signer - The person who is claming that he signed the message.
     * @param metaTx - the meta transaction object.
     * @param R S V - message signature.
     *
     * @notice - message that is hashed = "\x19\x01", getDomainSeperator(), messageHash
     */
    function verify(
        address signer,
        MetaTransaction memory metaTx,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) internal view returns (bool) {
        require(signer != address(0), "NativeMetaTransaction: INVALID_SIGNER");
        return
            signer == ecrecover(toTypedMessageHash(hashMetaTransaction(metaTx)), sigV, sigR, sigS);
    }
}
