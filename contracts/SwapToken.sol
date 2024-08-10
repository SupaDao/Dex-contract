//SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.0 < 0.9.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract SingleSwapToken{
      ISwapRouter public immutable swapRouter;


      constructor (address _routerAddress){
            //set the swap router
            swapRouter = ISwapRouter(_routerAddress);
      }

      function swapExactInputString (address _tokenA, address _tokenB, uint256 _amountIn, uint24 _poolFee) external returns (uint256 amountOut){
            TransferHelper.safeTransferFrom(_tokenA,msg.sender,address(this),_amountIn); 
            TransferHelper.safeApprove(_tokenA,address(swapRouter),_amountIn);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                  tokenIn: _tokenA,
                  tokenOut: _tokenB,
                  fee: _poolFee,
                  recipient:msg.sender,
                  deadline: block.timestamp,
                  amountIn:_amountIn,
                  amountOutMinimum: 0,
                  sqrtPriceLimitX96: 0
            });
            amountOut = swapRouter.exactInputSingle(params);
            return amountOut;
      }

      function swapExactOutputString (address _tokenA, address _tokenB, uint256 _amountOut,uint256 _amountInMaximum,uint24 _poolFee) external returns (uint256 amountIn){
            TransferHelper.safeTransferFrom(_tokenA,msg.sender,address(this),_amountInMaximum); 
            TransferHelper.safeApprove(_tokenA,address(swapRouter),_amountInMaximum);
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                  tokenIn: _tokenA,
                  tokenOut: _tokenB,
                  fee: _poolFee,
                  recipient:msg.sender,
                  deadline: block.timestamp,
                  amountOut:_amountOut,
                  amountInMaximum: _amountInMaximum,
                  sqrtPriceLimitX96: 0
            });
            amountIn = swapRouter.exactOutputSingle(params);
            if(amountIn < _amountInMaximum){
                  TransferHelper.safeApprove(_tokenA,address(swapRouter),0);
                  uint256 refunded = _amountInMaximum-amountIn;
                  TransferHelper.safeTransfer(_tokenA,msg.sender, refunded);
            }

            return amountIn;
      }
}