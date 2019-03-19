pragma solidity ^0.4.25;

/*******************************************************************************
 *
 * Copyright (c) 2019 Decentralization Authority MDAO.
 * Released under the MIT License.
 *
 * Pinbin - Metadata manager for the premier IPFS data pinning service.
 *
 * Version 19.3.18
 *
 * https://d14na.org
 * support@d14na.org
 */


/*******************************************************************************
 *
 * SafeMath
 */
library SafeMath {
    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }
    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    function div(uint a, uint b) internal pure returns (uint c) {
        require(b > 0);
        c = a / b;
    }
}


/*******************************************************************************
 *
 * ECRecovery
 *
 * Contract function to validate signature of pre-approved token transfers.
 * (borrowed from LavaWallet)
 */
contract ECRecovery {
    function recover(bytes32 hash, bytes sig) public pure returns (address);
}


/*******************************************************************************
 *
 * ERC Token Standard #20 Interface
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
 */
contract ERC20Interface {
    function totalSupply() public constant returns (uint);
    function balanceOf(address tokenOwner) public constant returns (uint balance);
    function allowance(address tokenOwner, address spender) public constant returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}


/*******************************************************************************
 *
 * ApproveAndCallFallBack
 *
 * Contract function to receive approval and execute function in one call
 * (borrowed from MiniMeToken)
 */
contract ApproveAndCallFallBack {
    function approveAndCall(address spender, uint tokens, bytes data) public;
    function receiveApproval(address from, uint256 tokens, address token, bytes data) public;
}


/*******************************************************************************
 *
 * Owned contract
 */
contract Owned {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner);

        emit OwnershipTransferred(owner, newOwner);

        owner = newOwner;

        newOwner = address(0);
    }
}


/*******************************************************************************
 *
 * Zer0netDb Interface
 */
contract Zer0netDbInterface {
    /* Interface getters. */
    function getAddress(bytes32 _key) external view returns (address);
    function getBool(bytes32 _key)    external view returns (bool);
    function getBytes(bytes32 _key)   external view returns (bytes);
    function getInt(bytes32 _key)     external view returns (int);
    function getString(bytes32 _key)  external view returns (string);
    function getUint(bytes32 _key)    external view returns (uint);

    /* Interface setters. */
    function setAddress(bytes32 _key, address _value) external;
    function setBool(bytes32 _key, bool _value) external;
    function setBytes(bytes32 _key, bytes _value) external;
    function setInt(bytes32 _key, int _value) external;
    function setString(bytes32 _key, string _value) external;
    function setUint(bytes32 _key, uint _value) external;

    /* Interface deletes. */
    function deleteAddress(bytes32 _key) external;
    function deleteBool(bytes32 _key) external;
    function deleteBytes(bytes32 _key) external;
    function deleteInt(bytes32 _key) external;
    function deleteString(bytes32 _key) external;
    function deleteUint(bytes32 _key) external;
}


/*******************************************************************************
 *
 * @notice Pinbin
 *
 * @dev IPFS data pinning.
 */
contract Pinbin is Owned {
    using SafeMath for uint;

    /* Initialize predecessor contract. */
    address private _predecessor;

    /* Initialize successor contract. */
    address private _successor;

    /* Initialize revision number. */
    uint private _revision;

    /* Initialize Zer0net Db contract. */
    Zer0netDbInterface private _zer0netDb;

    /* Set namespace. */
    string private _namespace = 'pinbin';

    event Collection(
        bytes32 indexed collectionId,
        address indexed owner,
        bytes data
    );

    event Bin(
        bytes32 indexed binId,
        address indexed owner,
        bytes data
    );

    /***************************************************************************
     *
     * Constructor
     */
    constructor() public {
        /* Initialize Zer0netDb (eternal) storage database contract. */
        // NOTE We hard-code the address here, since it should never change.
        // _zer0netDb = Zer0netDbInterface(0xE865Fe1A1A3b342bF0E2fcB11fF4E3BCe58263af);
        _zer0netDb = Zer0netDbInterface(0x4C2f68bCdEEB88764b1031eC330aD4DF8d6F64D6); // ROPSTEN

        /* Initialize (aname) hash. */
        bytes32 hash = keccak256(abi.encodePacked('aname.', _namespace));

        /* Set predecessor address. */
        _predecessor = _zer0netDb.getAddress(hash);

        /* Verify predecessor address. */
        if (_predecessor != 0x0) {
            /* Retrieve the last revision number (if available). */
            uint lastRevision = Pinbin(_predecessor).getRevision();

            /* Set (current) revision number. */
            _revision = lastRevision + 1;
        }
    }

    /**
     * @dev Only allow access to an authorized Zer0net administrator.
     */
    modifier onlyAuthBy0Admin() {
        /* Verify write access is only permitted to authorized accounts. */
        require(_zer0netDb.getBool(keccak256(
            abi.encodePacked(msg.sender, '.has.auth.for.', _namespace))) == true);

        _;      // function code is inserted here
    }

    /**
     * THIS CONTRACT DOES NOT ACCEPT DIRECT ETHER
     */
    function () public payable {
        /* Cancel this transaction. */
        revert('Oops! Direct payments are NOT permitted here.');
    }


    /***************************************************************************
     *
     * ACTIONS
     *
     */

    /**
     * Calculate Collection Id
     */
    function calcCollectionId(
        string _collectionTitle
    ) external view returns (bytes32 collectionId) {
        /* Calculate the collection id. */
        return calcCollectionId(msg.sender, _collectionTitle);
    }

    /**
     * Calculate Collection Id
     */
    function calcCollectionId(
        address _owner,
        string _collectionTitle
    ) public view returns (bytes32 collectionId) {
        /* Calculate the collection id. */
        collectionId = keccak256(abi.encodePacked(
            _namespace, ',',
            _owner, '.',
            _collectionTitle
        ));
    }

    /**
     * Calculate Bin Id
     */
    function calcBinId(
        string _collectionTitle,
        string _binTitle
    ) external view returns (bytes32 binId) {
        /* Retrieve bin id. */
        return calcBinId(msg.sender, _collectionTitle, _binTitle);
    }

    /**
     * Calculate Bin Id
     */
    function calcBinId(
        address _owner,
        string _collectionTitle,
        string _binTitle
    ) public view returns (bytes32 binId) {
        /* Retrieve collection id. */
        bytes32 collectionId = calcCollectionId(_owner, _collectionTitle);

        /* Retrieve bin id. */
        binId = calcBinId(collectionId, _binTitle);
    }

    /**
     * Calculate Bin Id
     */
    function calcBinId(
        bytes32 _collectionId,
        string _binTitle
    ) public view returns (bytes32 binId) {
        /* Calculate the bin id. */
        binId = keccak256(abi.encodePacked(
            _namespace, ',',
            _collectionId, '.',
            _binTitle
        ));
    }


    /***************************************************************************
     *
     * GETTERS
     *
     */

    /**
     * Get Collection
     */
    function getCollection(
        bytes32 _collectionId
    ) external view returns (
        address location,
        uint blockNum
    ) {
        /* Return collection. */
        return _getCollection(_collectionId);
    }

    /**
     * Get Collection
     */
    function getCollection(
        address _owner,
        string _collectionTitle
    ) external view returns (
        address location,
        uint blockNum
    ) {
        /* Retrieve collection id. */
        bytes32 collectionId = calcCollectionId(_owner, _collectionTitle);

        /* Return collection. */
        return _getCollection(collectionId);
    }

    /**
     * Get Collection
     *
     * Retrieves the encoded list of bins stored in the bytes array
     * associated with the specified `_collectionId`.
     */
    function _getCollection(
        bytes32 _collectionId
    ) private view returns (
        address location,
        uint blockNum
    ) {
        /* Retrieve location. */
        location = _zer0netDb.getAddress(_collectionId);

        /* Retrieve block number. */
        blockNum = _zer0netDb.getUint(_collectionId);
    }

    /**
     * Get Bin
     */
    function getBin(
        bytes32 _binId
    ) external view returns (
        address location,
        uint blockNum
    ) {
        /* Return bin metadata. */
        return _getBin(_binId);
    }

    /**
     * Get Bin
     */
    function getBin(
        bytes32 _collectionId,
        string _binTitle
    ) external view returns (
        address location,
        uint blockNum
    ) {
        /* Calculate the bin id. */
        bytes32 binId = keccak256(abi.encodePacked(
            _namespace, ',',
            _collectionId, '.',
            _binTitle
        ));

        /* Return bin metadata. */
        return _getBin(binId);
    }

    /**
     * Get Bin
     */
    function getBin(
        address _owner,
        string _collectionTitle,
        string _binTitle
    ) external view returns (
        address location,
        uint blockNum
    ) {
        /* Retrieve collection id. */
        bytes32 collectionId = calcCollectionId(_owner, _collectionTitle);

        /* Retrieve bin id. */
        bytes32 binId = calcBinId(collectionId, _binTitle);

        /* Return bin metadata. */
        return _getBin(binId);
    }

    /**
     * Get Bin (Metadata)
     *
     * Retrieves the location and block number of the bin data
     * stored for the specified `_binId`.
     *
     * NOTE: DApps can then read the `Pinned` event from the Ethereum
     *       Event Log, at the specified point, to recover the stored metadata.
     */
    function _getBin(
        bytes32 _binId
    ) private view returns (
        address location,
        uint blockNum
    ) {
        /* Retrieve location. */
        location = _zer0netDb.getAddress(_binId);

        /* Retrieve block number. */
        blockNum = _zer0netDb.getUint(_binId);
    }

    /**
     * Get Revision (Number)
     */
    function getRevision() public view returns (uint) {
        return _revision;
    }

    /**
     * Get Predecessor (Address)
     */
    function getPredecessor() public view returns (address) {
        return _predecessor;
    }

    /**
     * Get Successor (Address)
     */
    function getSuccessor() public view returns (address) {
        return _successor;
    }


    /***************************************************************************
     *
     * SETTERS
     *
     */

    /**
     * Save ALL
     *
     * Saves Bin data + Collection data.
     */
    function saveAll(
        string _collectionTitle,
        bytes _collectionData,
        string _binTitle,
        bytes _binData
    ) external returns (bool success) {
        /* Save all. */
        return saveAll(
            msg.sender,
            _collectionTitle,
            _collectionData,
            _binTitle,
            _binData
        );
    }

    /**
     * Save ALL
     *
     * Saves Bin data + Collection data.
     */
    function saveAll(
        address _owner,
        string _collectionTitle,
        bytes _collectionData,
        string _binTitle,
        bytes _binData
    ) public returns (bool success) {
        /* Save collection. */
        saveCollection(_owner, _collectionTitle, _collectionData);

        /* Save bin. */
        saveBin(_owner, _collectionTitle, _binTitle, _binData);

        /* Return success. */
        return true;
    }

    // TODO Add Relayer option, using ECRecovery / signatures.

    /**
     * Save Bin
     */
    function saveBin(
        string _collectionTitle,
        string _binTitle,
        bytes _data
    ) external returns (bool success) {
        /* Save bin. */
        return saveBin(
            msg.sender,
            _collectionTitle,
            _binTitle,
            _data
        );
    }

    /**
     * Save Bin
     */
    function saveBin(
        address _owner,
        string _collectionTitle,
        string _binTitle,
        bytes _data
    ) public returns (bool success) {
        /* Retrieve collection id. */
        bytes32 collectionId = calcCollectionId(_owner, _collectionTitle);

        /* Retrieve bin id. */
        bytes32 binId = calcBinId(collectionId, _binTitle);

        /* Save bin. */
        return _saveBin(_owner, binId, _data);
    }

    /**
     * Save Bin
     */
    function saveBin(
        bytes32 _collectionId,
        string _binTitle,
        bytes _data
    ) external returns (bool success) {
        /* Save bin. */
        return saveBin(
            msg.sender,
            _collectionId,
            _binTitle,
            _data
        );
    }

    /**
     * Save Bin
     */
    function saveBin(
        address _owner,
        bytes32 _collectionId,
        string _binTitle,
        bytes _data
    ) public returns (bool success) {
        /* Retrieve bin id. */
        bytes32 binId = calcBinId(_collectionId, _binTitle);

        /* Save bin. */
        return _saveBin(_owner, binId, _data);
    }

    // TODO Add Relayer option, using ECRecovery / signatures.

    /**
     * Save Bin
     */
    function _saveBin(
        address _owner,
        bytes32 _binId,
        bytes _data
    ) private returns (bool success) {
        /* Set location. */
        _zer0netDb.setAddress(_binId, address(this));

        /* Set block number. */
        _zer0netDb.setUint(_binId, block.number);

        /* Broadcast event. */
        emit Bin(_binId, _owner, _data);

        /* Return success. */
        return true;
    }

    /**
     * Save Collection
     */
    function saveCollection(
        string _title,
        bytes _data
    ) external returns (bool success) {
        /* Save collection. */
        return saveCollection(msg.sender, _title, _data);
    }

    /**
     * Save Collection
     */
    function saveCollection(
        address _owner,
        string _title,
        bytes _data
    ) public returns (bool success) {
        /* Calculate collection id. */
        // NOTE: We DO NOT permit external (pre-calculated) ids as input.
        bytes32 collectionId = calcCollectionId(_owner, _title);

        /* Save collection. */
        return _saveCollection(_owner, collectionId, _data);
    }

    // TODO Add Relayer option, using ECRecovery / signatures.

    /**
     * Save Collection
     *
     * NOTE: This performs a (possibly expensive) storage of up to 100
     *       bins, encoded as `bytes32 _binId`.
     *
     * On-chain (Estimated) Fees
     * -------------------------
     *
     * 1. 10,000 gas : Per increment in TOTAL collection(s) count
     * 2.  2,048 gas : Per (bytes32) hash in list
     * 3.     64 gas : Per byte stored (or is this 68??)
     *
     * eg. (Re-)saving a hash list of 100 entries would
     *     cost approx. 204,800 gas
     *     @ 5.0 Gwei will total approx. 1M gas
     *     @ $250 per ETH will cost approx. $0.25 USD
     *
     * IPFS (Estimated) Storage Rates
     * ------------------------------
     *
     * US$ 0.05 per 1GiB / month
     * US$50.00 per 1TiB / month
     *
     * NOTE: ALL rates include 2x data redundancy across a global
     *       storage network.
     *
     *       NO BANDWIDTH CHARGES ARE INCURRED OVER IPFS AT THIS TIME
     *
     *       The market rate for 1TiB of monthly storage from TOP
     *       cloud providers is currently $9.99/mo. With the exception
     *       of Amazon S3 Standard, currently $23.00/mo; and OneDrive
     *       priced below market at $6.99/mo.
     *
     */
    function _saveCollection(
        address _owner,
        bytes32 _collectionId,
        bytes _data
    ) private returns (bool success) {
        /* Set location. */
        _zer0netDb.setAddress(_collectionId, address(this));

        /* Set block number. */
        _zer0netDb.setUint(_collectionId, block.number);

        /* Broadcast event. */
        emit Collection(_collectionId, _owner, _data);

        /* Return success. */
        return true;
    }

    /**
     * Set Successor
     *
     * This is the contract address that replaced this current instnace.
     */
    function setSuccessor(
        address _newSuccessor
    ) onlyAuthBy0Admin external returns (bool success) {
        /* Set successor contract. */
        _successor = _newSuccessor;

        /* Return success. */
        return true;
    }


    /***************************************************************************
     *
     * INTERFACES
     *
     */

    /**
     * Supports Interface (EIP-165)
     *
     * (see: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-165.md)
     *
     * NOTE: Must support the following conditions:
     *       1. (true) when interfaceID is 0x01ffc9a7 (EIP165 interface)
     *       2. (false) when interfaceID is 0xffffffff
     *       3. (true) for any other interfaceID this contract implements
     *       4. (false) for any other interfaceID
     */
    function supportsInterface(
        bytes4 _interfaceID
    ) external pure returns (bool) {
        /* Initialize constants. */
        bytes4 InvalidId = 0xffffffff;
        bytes4 ERC165Id = 0x01ffc9a7;

        /* Validate condition #2. */
        if (_interfaceID == InvalidId) {
            return false;
        }

        /* Validate condition #1. */
        if (_interfaceID == ERC165Id) {
            return true;
        }

        // TODO Add additional interfaces here.

        /* Return false (for condition #4). */
        return false;
    }

    /**
     * ECRecovery Interface
     */
    function _ecRecovery() private view returns (
        ECRecovery ecrecovery
    ) {
        /* Initialize hash. */
        bytes32 hash = keccak256('aname.ecrecovery');

        /* Retrieve value from Zer0net Db. */
        address aname = _zer0netDb.getAddress(hash);

        /* Initialize interface. */
        ecrecovery = ECRecovery(aname);
    }


    /***************************************************************************
     *
     * UTILITIES
     *
     */

    /**
     * Bytes-to-Address
     *
     * Converts bytes into type address.
     */
    function _bytesToAddress(
        bytes _address
    ) private pure returns (address) {
        uint160 m = 0;
        uint160 b = 0;

        for (uint8 i = 0; i < 20; i++) {
            m *= 256;
            b = uint160(_address[i]);
            m += (b);
        }

        return address(m);
    }

    /**
     * Convert Bytes to Bytes32
     */
    function _bytesToBytes32(
        bytes _data,
        uint _offset
    ) private pure returns (bytes32 result) {
        /* Loop through each byte. */
        for (uint i = 0; i < 32; i++) {
            /* Shift bytes onto result. */
            result |= bytes32(_data[i + _offset] & 0xFF) >> (i * 8);
        }
    }

    /**
     * Convert Bytes32 to Bytes
     *
     * NOTE: Since solidity v0.4.22, you can use `abi.encodePacked()` for this,
     *       which returns bytes. (https://ethereum.stackexchange.com/a/55963)
     */
    function _bytes32ToBytes(
        bytes32 _data
    ) private pure returns (bytes result) {
        /* Pack the data. */
        return abi.encodePacked(_data);
    }

    /**
     * Transfer Any ERC20 Token
     *
     * @notice Owner can transfer out any accidentally sent ERC20 tokens.
     *
     * @dev Provides an ERC20 interface, which allows for the recover
     *      of any accidentally sent ERC20 tokens.
     */
    function transferAnyERC20Token(
        address _tokenAddress,
        uint _tokens
    ) public onlyOwner returns (bool success) {
        return ERC20Interface(_tokenAddress).transfer(owner, _tokens);
    }
}
