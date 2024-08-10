//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0 < 0.9.0;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";

contract LiquidityPool is IERC721Receiver{
      

      INonfungiblePositionManager public immutable nonfungiblePositionManager;

      // @notice Represent the deposit of the nft
      struct Deposit {
            address owner;
            uint128 liquidity;
            address tokenA;
            address tokenB;
      }

      event LiquidityAdded(uint256 tokenId, uint128 liquidity,uint256 amountA, uint256 amountB, address indexed provider);

      constructor (address _nonfungiblePositionManager){
            nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
      }

      /**
       * @dev deposit[tokenId] => Deposit
       */
      mapping(uint256 => Deposit) public deposits;

      //Implementing "onERC721";
      function onERC721Received(address _operator, address, uint256 _tokenId, bytes calldata) external override returns(bytes4){
            _createDeposit(_operator,_tokenId);
            return this.onERC721Received.selector;
      }

      function mintNewPosition(address _tokenA, address _tokenB,uint24 _fee,int24 _tickLower, int24 _tickUpper, uint256 _amountA, uint256 _amountB ) external returns (
            uint256 _tokenId, 
            uint128 liquidity,
            uint256 amountA,
            uint256 amountB
            ){
                  //Approve positon manager
                  TransferHelper.safeApprove(_tokenA, address(nonfungiblePositionManager), _amountA);

                  TransferHelper.safeApprove(_tokenB, address(nonfungiblePositionManager), _amountB);
                  INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                        token0:_tokenA,
                        token1:_tokenB,
                        fee:_fee,
                        tickLower: _tickLower,
                        tickUpper: _tickUpper,
                        amount0Desired: _amountA,
                        amount1Desired: _amountB,
                        amount0Min:0,
                        amount1Min:0,
                        recipient:address(this),
                        deadline:block.timestamp
                  });
                  (_tokenId,liquidity,amountA,amountB) = nonfungiblePositionManager.mint(params);

                  //create deposit
                  _createDeposit(msg.sender, _tokenId);
                  if (amountA <_amountA){
                        TransferHelper.safeApprove(_tokenA, address(nonfungiblePositionManager), 0);
                        uint256 refundA = _amountA - amountA;
                        TransferHelper.safeTransfer(_tokenA, msg.sender, refundA);
                  }
                  if (amountB <_amountB){
                        TransferHelper.safeApprove(_tokenB, address(nonfungiblePositionManager), 0);
                        uint256 refundB = _amountB - amountB;
                        TransferHelper.safeTransfer(_tokenB, msg.sender, refundB);
                  }

                  emit LiquidityAdded(_tokenId,liquidity,amountA,amountB,msg.sender);

                  return (_tokenId,liquidity,amountA,amountB);
            }
            
      function collectAllFees(uint256 _tokenId) external returns(uint256 amountA, uint256 amountB){
            INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
                  tokenId:_tokenId,
                  recipient:address(this),
                  amount0Max: type(uint128).max,
                  amount1Max: type(uint128).max
                  }) ;
            
            (amountA,amountB) = nonfungiblePositionManager.collect(params);
            _sendOwner(_tokenId,amountA,amountB);
            return (amountA,amountB);
      }

      function increaseLiquidityCurrentRange (uint256 _tokenId, uint256 _amountAddA,uint256 _amountAddB) external returns(uint128 liquidity,uint256 amountA,uint256 amountB){
            address tokenA = deposits[_tokenId].tokenA;
            address tokenB = deposits[_tokenId].tokenB;
            TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), _amountAddA);
            TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), _amountAddB);

            TransferHelper.safeApprove(tokenA, address(nonfungiblePositionManager), _amountAddA);
            TransferHelper.safeApprove(tokenB, address(nonfungiblePositionManager), _amountAddB);

            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
                  tokenId:_tokenId,
                  amount0Desired: _amountAddA,
                  amount1Desired: _amountAddB,
                  amount0Min:0,
                  amount1Min:0,
                  deadline:block.timestamp
            });

            (liquidity,amountA,amountB) = nonfungiblePositionManager.increaseLiquidity(params);
            return (liquidity,amountA,amountB);
      }

      function getLiquidity(uint256 _tokenId) external view returns(uint128){
            (,,,,,,,uint128 liquidity,,,,) = nonfungiblePositionManager.positions(_tokenId);
            return liquidity;
      }


      function decreaseLiquidityCurrentRange (uint128 _liquidity,uint256 _tokenId) external returns(uint256 amountA, uint256 amountB){
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
                  tokenId:_tokenId,
                  liquidity: _liquidity,
                  amount0Min:0,
                  amount1Min:0,
                  deadline:block.timestamp
            });
            (amountA,amountB) = nonfungiblePositionManager.decreaseLiquidity(params);
            _sendOwner(_tokenId,amountA,amountB);
            return(amountA,amountB);
      }


      function _createDeposit(address _owner, uint256 _tokenId) internal {
            (,,address tokenA,address tokenB,,,,uint128 liquidity,,,,) = nonfungiblePositionManager.positions((_tokenId));
            // set the owner and data for position
            //operator is msg.sender;
            deposits[_tokenId] = Deposit({
                  owner:_owner,
                  liquidity:liquidity,
                  tokenA:tokenA,
                  tokenB:tokenB
                  });
      }

      function _sendOwner(uint256 _tokenId, uint256 _amountA, uint256 _amountB) internal{
            // get the owner of the position
            address owner = deposits[_tokenId].owner;
            // transfer the tokens to the owner
            address tokenA = deposits[_tokenId].tokenA;
            address tokenB = deposits[_tokenId].tokenB;

            TransferHelper.safeTransfer(tokenA,owner,_amountA);
            TransferHelper.safeTransfer(tokenB,owner,_amountB);
      }

}