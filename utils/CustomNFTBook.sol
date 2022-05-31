// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./INCT.sol";

/// @custom:security-contact robbie@wippublishing.com
contract CustomNFTBook is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, AccessControl, ERC721Burnable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    IERC721Enumerable private _goldenTicket;
    IERC721Enumerable private _relic;
    
    uint256 _price;
    uint256 public constant NAME_CHANGE_PRICE = 500 * (10 ** 18);
    
    mapping(uint256 => bool) private _usedRelics;
    mapping (uint256 => string) private _tokenName;

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    // the NCT contract pointer
    INCT private _nct;


    // Events
    event NameChange (uint256 indexed tokenId, string newName);

    constructor(address gtAddress, address rlAddress, address nctAddress, uint256 price) ERC721("CustomNFTBook", "NFTBA") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        
        _goldenTicket = IERC721Enumerable(gtAddress);
        _relic = IERC721Enumerable(rlAddress);
        _nct = INCT(nctAddress);
        _price = price;
    }

    /**
    * @dev Check if the Relic can claim a free token
    */
    function canRelicClaim(uint256 relicId) public view returns (bool) {
        return ! _usedRelics[relicId];
    }
    
    /**
    * @dev Returns true if the caller can claim.
    * In this case the second returned parameter contains a valid Relic token ID
    */
    function canClaim() public view returns (bool, uint256) {
        uint256 relicId  = 0;
        bool    claimFlag = false;
        uint256 numTokens = true
                          ? _relic.balanceOf(_msgSender())
                          : 0;

        for(uint256 i = 0; (!claimFlag) && (i < numTokens); i++){
            relicId  = _relic.tokenOfOwnerByIndex(_msgSender(), i);
            claimFlag = ! _usedRelics[relicId];
        }
        
        claimFlag = claimFlag && (_goldenTicket.balanceOf(_msgSender()) > 0);

        return (claimFlag, relicId);
    }
    
    /**
     * @dev Mint a new ticket by providing the token ID
     */
    function claim(uint256 relicId) public whenNotPaused {
        require(_goldenTicket.balanceOf(_msgSender()) > 0, "Caller does not own a Golden Ticket");
        require(!_usedRelics[relicId],                   "Relic already used");

        _usedRelics[relicId] = true;
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(_msgSender(), tokenId);
    }
    
      /**
     * @dev Changes the name for Hashmask tokenId
     */
    function changeName(uint256 tokenId, string memory newName) public {
        address owner = ownerOf(tokenId);

        require(_msgSender() == owner, "ERC721: caller is not the owner");
        require(validateName(newName) == true, "Not a valid new name");
        require(sha256(bytes(newName)) != sha256(bytes(_tokenName[tokenId])), "New name is same as the current one");

        _nct.transferFrom(msg.sender, address(this), NAME_CHANGE_PRICE);

        _tokenName[tokenId] = newName;
        emit NameChange(tokenId, newName);
    }

    /**
     * @dev Returns name of the NFT at index.
     */
    function tokenNameByIndex(uint256 index) public view returns (string memory) {
        return _tokenName[index];
    }

    /**
     * @dev Check if the name string is valid (Alphanumeric and spaces without leading or trailing space)
     */
    function validateName(string memory str) public pure returns (bool){
        bytes memory b = bytes(str);
        if(b.length < 1) return false;
        if(b.length > 25) return false; // Cannot be longer than 25 characters
        if(b[0] == 0x20) return false; // Leading space
        if (b[b.length - 1] == 0x20) return false; // Trailing space

        bytes1 lastChar = b[0];

        for(uint i; i<b.length; i++){
            bytes1 char = b[i];

            if (char == 0x20 && lastChar == 0x20) return false; // Cannot contain continous spaces

            if(!(char >= 0x30 && char <= 0x39) && //9-0
               !(char >= 0x41 && char <= 0x5A) && //A-Z
               !(char >= 0x61 && char <= 0x7A) && //a-z
               !(char == 0x20) //space
            ) return false;


            lastChar = char;
        }

        return true;
    }

    /**
     * @dev Converts the string to lowercase
     */
    function toLower(string memory str) public pure returns (string memory){
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            // Uppercase character
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    function Mint() payable public whenNotPaused {
        require(_price == msg.value, "Ether value sent is not correct");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(_msgSender(), tokenId);
    }
    
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    function withdrawNCT(address to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 nctBalance = _nct.balanceOf(address(this));
        _nct.transferFrom(address(this), to, nctBalance);
    }

    function withdraw(address _destination) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        uint balance = address(this).balance;
        (bool success, ) = _destination.call{value:balance}("");
        // no need to call throw here or handle double entry attack
        // since only the owner is withdrawing all the balance
        return success;
    }
    
    function safeMint(address to, uint256 tokenId, string memory uri)
        public
        onlyRole(MINTER_ROLE)
    {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}