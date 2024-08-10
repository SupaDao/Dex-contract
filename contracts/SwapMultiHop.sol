//SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.0 < 0.9.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract SwapMultiHop{
      ISwapRouter public immutable swapRouter;
      //uint24 public immutable fee;

      constructor (address _routerAddress){
            //set the swap router
            swapRouter = ISwapRouter(_routerAddress);
      }

      function swapExactInputMultiHop(address _tokenA, address _tokenB, uint256 _amountIn,uint24[] calldata _fees, address[] calldata _tokens) external returns (uint256 amountOut){
            bytes memory path = buildPathInput(_tokenA, _fees, _tokens, _tokenB);
            TransferHelper.safeTransferFrom(_tokenA,msg.sender,address(this),_amountIn); 
            TransferHelper.safeApprove(_tokenA,address(swapRouter),_amountIn);

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                  path: path,
                  recipient:msg.sender,
                  deadline: block.timestamp,
                  amountIn:_amountIn,
                  amountOutMinimum: 0
            });

            amountOut = swapRouter.exactInput(params);
            return amountOut;
      }

      function swapExactOutputMultiHop(address _tokenA, address _tokenB, uint256 _amountOut, uint256 _amountInMaximum, uint24[] calldata _fees, address[] calldata _tokens) external returns (uint256 amountIn){
            bytes memory path = buildPathOutput(_tokenA, _fees, _tokens, _tokenB);
            TransferHelper.safeTransferFrom(_tokenA,msg.sender,address(this),_amountInMaximum); 
            TransferHelper.safeApprove(_tokenA,address(swapRouter),_amountInMaximum);

            ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
                  path: path,
                  recipient: msg.sender,
                  deadline: block.timestamp,
                  amountOut: _amountOut,
                  amountInMaximum: _amountInMaximum
            });

            amountIn = swapRouter.exactOutput(params);
            if(amountIn < _amountInMaximum){
                  TransferHelper.safeApprove(_tokenA,address(swapRouter),0);
                  uint256 refunded = _amountInMaximum-amountIn;
                  TransferHelper.safeTransferFrom(_tokenA,address(this),msg.sender,refunded);
            }
      }

      // Helper function
      function buildPathInput (address _tokenA,uint24[] calldata _fees, address[] calldata _tokens, address _tokenB) internal pure returns(bytes memory){
            bytes memory path = abi.encodePacked(_tokenA);
            for (uint256 i = 0; i< _fees.length; i++){
                  path = abi.encodePacked(path,_fees[i],_tokens[i]);
            }
            path= abi.encodePacked(path, _tokenB);
            return path;
      }

      function buildPathOutput (address _tokenA,uint24[] calldata _fees, address[] calldata _tokens, address _tokenB) internal pure returns(bytes memory){
            bytes memory path = abi.encodePacked(_tokenB);
            for (uint256 i = _fees.length; i> 0; i--){
                  path = abi.encodePacked(path,_fees[i-1],_tokens[i-1]);
            }
            path= abi.encodePacked(path, _tokenA);
            return path;
      }
}