// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFTBase is ERC721, ERC721URIStorage, ERC721Burnable, Ownable {
    uint256 public mintFee;
    address public nftFactory;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    constructor(string memory _name, string memory _symbol, uint256 _mintFee,address _owner,address _factory)
    ERC721(_name,_symbol)
    Ownable(_owner)
    {
        mintFee = _mintFee;
        nftFactory = _factory;
    }

    function safeMint (address to,string memory uri) public payable {
        require(msg.value >= mintFee, "Insufficient Mint Fee");
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to,tokenId);
        _setTokenURI(tokenId, uri);
        payable(nftFactory).transfer(address(this).balance);
    }

    function safeMintCollection (address to, string[] memory uris) public payable {
        require(msg.value >= mintFee, "Insufficient Mint Fee");
        for (uint256 i = 0; i < uris.length; i++) 
        {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to,tokenId);
            _setTokenURI(tokenId, uris[i]);    
        }
        payable(nftFactory).transfer(address(this).balance);
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
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
