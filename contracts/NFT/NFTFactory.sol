// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {NFTBase} from "./NFTBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

contract NFTFactory is Ownable {
    mapping(address => address[]) internal  UserNFTs;
    uint256 public creationFee; // Fee to deploy a new NFT contract
    uint256 public mintFee; 

    event NFTContractCreated(address indexed creator, address nftContract);
    event FeeUpdated(string feeType, uint256 newFee);

    constructor(uint256 _creationFee, uint256 _mintFee) Ownable(msg.sender) {
        creationFee = _creationFee;
        mintFee = _mintFee;
    }

    function createNFTContract(string memory _name, string memory _symbol) public payable returns (address){
        require(msg.value >= creationFee, "Insufficient fee to create NFT contract");
        bytes memory bytecode = abi.encodePacked(
            type(NFTBase).creationCode,
            abi.encode(_name, _symbol, mintFee,msg.sender,address(this))
        );

        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(deployed) { revert(0, 0) }
        }

        UserNFTs[msg.sender].push(deployed);
        emit NFTContractCreated(msg.sender,deployed);
        return deployed;
    }

    function setMintFee (uint256 _fee) external onlyOwner{
        require(_fee >= 0, "Mint fee should have a value");
        mintFee = _fee;
        emit FeeUpdated("Mint Fee", _fee);
    }

    function setCreationFee (uint256 _fee) external onlyOwner{
        require(_fee >= 0, "Mint fee should have a value");
        creationFee = _fee;
        emit FeeUpdated("Creation Fee", _fee);
    }


    // Withdrawal function
    function withdrawFees() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function getUserNFT (address owner) public view returns (address[] memory){
        return UserNFTs[owner];
    }

    receive() external payable {}
}
