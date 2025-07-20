// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IPool} from "../core/interfaces/IPool.sol";
import {PoolAddress} from "../libraries/PoolAddress.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";
import {LiquidityManagement} from "../base/LiquidityManagement.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {Multicall} from "../base/Multicall.sol";
import {ImutableState} from "../base/ImutableStates.sol";
import {SelfPermit} from "../base/SelfPermit.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {FixedPoint128} from "../libraries/FixedPoint128.sol";
import {INonfungibleTokenPositionManager} from "./interfaces/INonfungibleTokenPositionManager.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoolInitializer} from "../base/PoolInitializer.sol";
import {ERC721Permit} from "../base/ERC721Permit.sol";
import {INonfungibleTokenPositionDescriptor} from "./interfaces/INonfungibleTokenPositionDescriptor.sol";
import {ProtocolFees} from "../governance/ProtocolFees.sol";

contract NonfungibleTokenPositionManager is
    INonfungibleTokenPositionManager,
    ERC721Permit,
    Multicall,
    LiquidityManagement,
    PoolInitializer,
    ReentrancyGuard,
    SelfPermit
{
    struct Position {
        uint96 nonce;
        address operator;
        uint80 poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    mapping(uint256 => Position) public _positions;
    mapping(address => uint80) private _poolIds;
    uint176 private _nextId = 1;
    uint80 private _nextPoolId = 1;
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    address private immutable _tokenDescriptor;

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionExpired();
        _;
    }

    modifier isAuthorizedForToken(uint256 tokenId) {
        if (!_isAuthorized(msg.sender, address(this), tokenId)) revert NotApproved();
        _;
    }

    constructor(address _factory, address _WETH9, address _tokenDescriptor_)
        ERC721Permit("SupaSwap Position", "SSP-POS", "1")
        ImutableState(_factory, _WETH9)
    {
        _tokenDescriptor = _tokenDescriptor_;
    }

    function positions(uint256 tokenId)
        external
        view
        override
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        if (position.poolId == 0) revert InvalidToken();
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            position.nonce,
            position.operator,
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function cachePoolKey(address pool, PoolAddress.PoolKey memory poolKey) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }

    function mint(MintParams calldata params)
        external
        payable
        override
        nonReentrant
        checkDeadline(params.deadline)
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        IPool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );
        _mint(params.recipient, (tokenId = _nextId++));

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.tickLower, params.tickUpper));
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) = pool.getPositions(positionKey);

        uint80 poolId = cachePoolKey(
            address(pool), PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee})
        );
        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            poolId: poolId,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        emit PositionMinted(tokenId, params.recipient, poolId, params.tickLower, params.tickUpper, liquidity);
        emit LiquidityIncreased(tokenId, liquidity, amount0, amount1);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId));
        return INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(this, tokenId);
    }

    function baseURI() public view returns (string memory) {
        return _baseURI();
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        nonReentrant
        checkDeadline(params.deadline)
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position storage position = _positions[params.tokenId];
        if (msg.sender != position.operator && msg.sender != _ownerOf(params.tokenId)) revert NotAuthorized();
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IPool pool = IPool(PoolAddress.computeAddress(factory, poolKey.token0, poolKey.token1, poolKey.fee));

        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                recipient: address(this),
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        bytes32 positionKey = _computeKey(position.tickLower, position.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) = pool.getPositions(positionKey);

        position.tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128
            )
        );
        position.tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity += liquidity;

        emit LiquidityIncreased(params.tokenId, liquidity, amount0, amount1);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        nonReentrant
        isAuthorizedForToken(params.tokenId)
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        if (params.liquidity == 0) revert InvalidAmount();
        Position storage position = _positions[params.tokenId];

        if (position.liquidity < params.liquidity) revert InsufficientLiquidity();
        if (msg.sender != position.operator && msg.sender != _ownerOf(params.tokenId)) revert NotAuthorized();
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IPool pool = IPool(PoolAddress.computeAddress(factory, poolKey.token0, poolKey.token1, poolKey.fee));

        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert SlipageCheck();

        bytes32 positionKey = _computeKey(position.tickLower, position.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) = pool.getPositions(positionKey);

        position.tokensOwed0 += uint128(amount0)
            + uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128
                )
            );
        position.tokensOwed1 += uint128(amount1)
            + uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128
                )
            );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity = position.liquidity - params.liquidity;

        emit LiquidityDecreased(params.tokenId, params.liquidity, amount0, amount1);
    }

    function collect(CollectParams calldata params)
        external
        payable
        override
        nonReentrant
        isAuthorizedForToken(params.tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        Position storage position = _positions[params.tokenId];
        if (msg.sender != _ownerOf(params.tokenId) && msg.sender != position.operator) revert NotAuthorized();
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IPool pool = IPool(PoolAddress.computeAddress(factory, poolKey.token0, poolKey.token1, poolKey.fee));

        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) =
                pool.getPositions(_computeKey(position.tickLower, position.tickUpper));

            tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128
                )
            );
            tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128
                )
            );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }

        (uint128 amount0Collect, uint128 amount1Collect) = (
            params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
            params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
        );

        (amount0, amount1) =
            pool.collect(recipient, position.tickLower, position.tickUpper, amount0Collect, amount1Collect);

        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

        emit TokensCollected(params.tokenId, recipient, amount0Collect, amount1Collect);
    }

    function burn(uint256 tokenId) external payable override nonReentrant isAuthorizedForToken(tokenId) {
        address owner = _ownerOf(tokenId);
        if (msg.sender != owner) revert NotAuthorized();
        Position storage position = _positions[tokenId];
        if (position.liquidity != 0) revert LiquidityNotZero();
        if (position.tokensOwed0 != 0 || position.tokensOwed1 != 0) revert FeesOwed();
        delete _positions[tokenId];
        _burn(tokenId);
        emit PositionBurned(tokenId, owner);
    }

    function _computeKey(int24 tickLower, int24 tickUpper) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }

    function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _positions[tokenId].operator;
    }

    function _approve(address to, uint256 tokenId) internal {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function tokenByIndex(uint256 index) external view override returns (uint256) {}
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {}
    function totalSupply() external view returns (uint256) {}

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function getFactory() external view override returns (address) {
        return factory;
    }
}
