// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UserProfile
 * @notice On-chain user profile storage for Poline DAO
 * @dev Stores user preferences, avatar, delegate info, and social links
 *      Designed with extensible JSON fields to avoid future redeployments
 */
contract UserProfile {
    /// @notice Profile data structure
    struct Profile {
        string avatarURI; // NFT tokenURI, IPFS hash, or empty for identicon
        string displayName; // User's display name (max 32 chars recommended)
        string bio; // Short biography (max 280 chars recommended)
        string socialLinks; // JSON: {"twitter":"@handle","telegram":"@handle","discord":"user#1234","website":"https://..."}
        string preferences; // JSON: {"theme":"dark","language":"pt-BR","currency":"BRL","hideBalances":false,"hideSmallTokens":false}
        uint8 avatarType; // 0 = identicon (default), 1 = NFT, 2 = custom IPFS
        bool isDelegate; // Whether user accepts delegations
        string delegateStatement; // Statement for delegate marketplace
        uint256 updatedAt; // Last update timestamp
    }

    /// @notice User address => Profile data
    mapping(address => Profile) public profiles;

    /// @notice Display name => User address (for ENS-like lookups)
    /// @dev Names are stored lowercase for case-insensitive lookups
    mapping(string => address) public nameToAddress;

    /// @notice Emitted when a user updates their profile
    event ProfileUpdated(address indexed user, uint256 timestamp);

    /// @notice Emitted when a user changes their delegate status
    event DelegateStatusChanged(address indexed user, bool isDelegate);

    /// @notice Emitted when a user claims a display name
    event NameClaimed(address indexed user, string name);

    /// @notice Emitted when a user releases a display name
    event NameReleased(address indexed user, string name);

    error NameAlreadyTaken(string name);
    error NameTooShort();
    error NameTooLong();
    error InvalidCharacter();

    /// @notice Set the complete profile (gas-intensive, use specific setters when possible)
    /// @param _profile The complete profile data
    function setProfile(Profile calldata _profile) external {
        // Handle name change
        string memory oldName = profiles[msg.sender].displayName;
        string memory newName = _profile.displayName;

        if (bytes(newName).length > 0) {
            _validateAndClaimName(newName, oldName);
        } else if (bytes(oldName).length > 0) {
            // Releasing old name
            delete nameToAddress[_toLower(oldName)];
            emit NameReleased(msg.sender, oldName);
        }

        profiles[msg.sender] = _profile;
        profiles[msg.sender].updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, block.timestamp);

        if (_profile.isDelegate != profiles[msg.sender].isDelegate) {
            emit DelegateStatusChanged(msg.sender, _profile.isDelegate);
        }
    }

    /// @notice Set only the avatar (cheaper than full profile update)
    /// @param _uri Avatar URI (NFT tokenURI, IPFS hash, or empty)
    /// @param _avatarType 0 = identicon, 1 = NFT, 2 = custom
    function setAvatar(string calldata _uri, uint8 _avatarType) external {
        profiles[msg.sender].avatarURI = _uri;
        profiles[msg.sender].avatarType = _avatarType;
        profiles[msg.sender].updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, block.timestamp);
    }

    /// @notice Set display name and bio
    /// @param _displayName User's display name
    /// @param _bio User's biography
    function setNameAndBio(
        string calldata _displayName,
        string calldata _bio
    ) external {
        string memory oldName = profiles[msg.sender].displayName;

        if (bytes(_displayName).length > 0) {
            _validateAndClaimName(_displayName, oldName);
        } else if (bytes(oldName).length > 0) {
            delete nameToAddress[_toLower(oldName)];
            emit NameReleased(msg.sender, oldName);
        }

        profiles[msg.sender].displayName = _displayName;
        profiles[msg.sender].bio = _bio;
        profiles[msg.sender].updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, block.timestamp);
    }

    /// @notice Set delegate information
    /// @param _isDelegate Whether user accepts delegations
    /// @param _statement Delegate statement for marketplace
    function setDelegateInfo(
        bool _isDelegate,
        string calldata _statement
    ) external {
        profiles[msg.sender].isDelegate = _isDelegate;
        profiles[msg.sender].delegateStatement = _statement;
        profiles[msg.sender].updatedAt = block.timestamp;

        emit DelegateStatusChanged(msg.sender, _isDelegate);
        emit ProfileUpdated(msg.sender, block.timestamp);
    }

    /// @notice Set user preferences (theme, language, etc.)
    /// @param _preferences JSON string with preferences
    function setPreferences(string calldata _preferences) external {
        profiles[msg.sender].preferences = _preferences;
        profiles[msg.sender].updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, block.timestamp);
    }

    /// @notice Set social links
    /// @param _socialLinks JSON string with social links
    function setSocialLinks(string calldata _socialLinks) external {
        profiles[msg.sender].socialLinks = _socialLinks;
        profiles[msg.sender].updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, block.timestamp);
    }

    /// @notice Get complete profile for a user
    /// @param _user Address to lookup
    /// @return The user's profile
    function getProfile(address _user) external view returns (Profile memory) {
        return profiles[_user];
    }

    /// @notice Get address by display name (case-insensitive)
    /// @param _name Display name to lookup
    /// @return User address (zero address if not found)
    function getAddressByName(
        string calldata _name
    ) external view returns (address) {
        return nameToAddress[_toLower(_name)];
    }

    /// @notice Check if a name is available
    /// @param _name Name to check
    /// @return True if available
    function isNameAvailable(
        string calldata _name
    ) external view returns (bool) {
        if (bytes(_name).length < 3 || bytes(_name).length > 32) {
            return false;
        }
        return nameToAddress[_toLower(_name)] == address(0);
    }

    /// @notice Get multiple profiles in one call (for lists)
    /// @param _users Array of addresses
    /// @return Array of profiles
    function getProfiles(
        address[] calldata _users
    ) external view returns (Profile[] memory) {
        Profile[] memory result = new Profile[](_users.length);
        for (uint256 i = 0; i < _users.length; i++) {
            result[i] = profiles[_users[i]];
        }
        return result;
    }

    // ============ Internal Functions ============

    function _validateAndClaimName(
        string memory _newName,
        string memory _oldName
    ) internal {
        bytes memory nameBytes = bytes(_newName);

        if (nameBytes.length < 3) revert NameTooShort();
        if (nameBytes.length > 32) revert NameTooLong();

        // Validate characters (alphanumeric, underscore, dash only)
        for (uint256 i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            bool isValid = (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A) || // a-z
                char == 0x5F || // _
                char == 0x2D; // -
            if (!isValid) revert InvalidCharacter();
        }

        string memory lowerNew = _toLower(_newName);
        string memory lowerOld = _toLower(_oldName);

        // Check if it's actually a different name
        if (keccak256(bytes(lowerNew)) != keccak256(bytes(lowerOld))) {
            // Check availability
            if (nameToAddress[lowerNew] != address(0)) {
                revert NameAlreadyTaken(_newName);
            }

            // Release old name if exists
            if (bytes(_oldName).length > 0) {
                delete nameToAddress[lowerOld];
                emit NameReleased(msg.sender, _oldName);
            }

            // Claim new name
            nameToAddress[lowerNew] = msg.sender;
            emit NameClaimed(msg.sender, _newName);
        }
    }

    function _toLower(
        string memory _str
    ) internal pure returns (string memory) {
        bytes memory bStr = bytes(_str);
        bytes memory bLower = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
}
