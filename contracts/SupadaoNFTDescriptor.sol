//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0 < 0.9.0;
pragma abicoder v2;


import "@uniswap/v3-periphery/contracts/libraries/NFTDescriptor.sol";

contract SupadaoNFTDescriptor {
      using NFTDescriptor for *;

      function constructTokenURI(NFTDescriptor.ConstructTokenURIParams memory params) public pure returns (string memory){
            return NFTDescriptor.constructTokenURI(params);
      }

      function escapeQuotes(string memory symbol) internal pure returns (string memory){
            return NFTDescriptor.escapeQuotes(symbol);
      }

      function tickToDecimalString(
            int24 tick,
            int24 tickSpacing,
            uint8 baseTokenDecimals,
            uint8 quoteTokenDecimals,
            bool flipRatio
      )internal pure returns (string memory){
            return NFTDescriptor.tickToDecimalString(tick, tickSpacing, baseTokenDecimals, quoteTokenDecimals, flipRatio);
      }

      function fixedPointToDecimalString(
            uint160 sqrtRatioX96,
            uint8 baseTokenDecimals,
            uint8 quoteTokenDecimals
      ) internal pure returns (string memory){
            return NFTDescriptor.fixedPointToDecimalString(sqrtRatioX96, baseTokenDecimals, quoteTokenDecimals);
      }

      function feeToPercentString(uint24 fee) internal pure returns (string memory){
            return NFTDescriptor.feeToPercentString(fee);
      }

      function addressToString(address addr) internal pure returns (string memory){
            return NFTDescriptor.addressToString(addr);
      }

      function generateSVGImage(NFTDescriptor.ConstructTokenURIParams memory params) internal pure returns (string memory svg){
            return NFTDescriptor.generateSVGImage(params);
      }

      function tokenToColorHex(uint256 token, uint256 offset) internal pure returns (string memory str) {
            return NFTDescriptor.tokenToColorHex(token, offset);
      }

      function getCircleCoord(
            uint256 tokenAddress,
            uint256 offset,
            uint256 tokenId
      ) internal pure returns (uint256){
            return NFTDescriptor.getCircleCoord(tokenAddress, offset, tokenId);
      }

      function sliceTokenHex(uint256 token, uint256 offset) internal pure returns (uint256) {
            return NFTDescriptor.sliceTokenHex(token, offset);
      }
}