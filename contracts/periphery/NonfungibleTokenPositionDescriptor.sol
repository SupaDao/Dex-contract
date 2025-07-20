// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPool} from "../core/interfaces/IPool.sol";
import {ChainId} from "../libraries/ChainId.sol";
import {INonfungibleTokenPositionDescriptor} from "./interfaces/INonfungibleTokenPositionDescriptor.sol";
import {INonfungibleTokenPositionManager} from "./interfaces/INonfungibleTokenPositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolAddress} from "../libraries/PoolAddress.sol";
import {NFTDescriptor} from "../libraries/NFTDescriptor.sol";
import {TokenRatioSortOrder} from "../libraries/TokenRatioSortOrder.sol";
import {SafeERC20Namer} from "../libraries/SafeERC20Namer.sol";

contract NonfungibleTokenPositionDescriptor is INonfungibleTokenPositionDescriptor {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant TBTC = 0x8dAEBADE922dF735c38C80C7eBD708Af50815fAa;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address public immutable WETH9;
    bytes32 public immutable nativeCurrencyLabelBytes;

    constructor(address _WETH9, bytes32 _nativeCurrencyLabelBytes) {
        WETH9 = _WETH9;
        nativeCurrencyLabelBytes = _nativeCurrencyLabelBytes;
    }

    /// @notice Returns the native currency label as a string
    function nativeCurrencyLabel() public view returns (string memory) {
        uint256 len = 0;
        while (len < 32 && nativeCurrencyLabelBytes[len] != 0) {
            len++;
        }
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = nativeCurrencyLabelBytes[i];
        }
        return string(b);
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    function tokenURI(INonfungibleTokenPositionManager positionManager, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        // Fetch position data
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) =
            positionManager.positions(tokenId);

        // Compute pool address
        address poolAddress = PoolAddress.computeAddress(address(positionManager.getFactory()), token0, token1, fee);
        IPool pool = IPool(poolAddress);

        // Get token order
        (address quoteTokenAddress, address baseTokenAddress, bool flipRatio) = getTokenOrder(token0, token1);

        // Get pool data
        (int24 tickCurrent, int24 tickSpacing) = getPoolData(pool);

        // Construct token URI params in parts
        NFTDescriptor.ConstructTokenURIParams memory params =
            createTokenURIParamsPart1(tokenId, quoteTokenAddress, baseTokenAddress, flipRatio, tickLower, tickUpper);
        params = createTokenURIParamsPart2(params, tickCurrent, tickSpacing, fee, poolAddress);

        // Construct and return token URI
        return NFTDescriptor.constructTokenURI(params);
    }

    /// @dev Determines the token order based on flipRatio
    function getTokenOrder(address token0, address token1)
        private
        view
        returns (address quoteTokenAddress, address baseTokenAddress, bool flipRatio)
    {
        flipRatio = _flipRatio(token0, token1, ChainId.get());
        quoteTokenAddress = !flipRatio ? token1 : token0;
        baseTokenAddress = !flipRatio ? token0 : token1;
    }

    /// @dev Fetches pool data (tickCurrent and tickSpacing)
    function getPoolData(IPool pool) private view returns (int24 tickCurrent, int24 tickSpacing) {
        (, tickCurrent,,,,,) = pool.getSlot0();
        tickSpacing = pool.getTickSpacing();
    }

    /// @dev Creates the first part of the token URI parameters
    function createTokenURIParamsPart1(
        uint256 tokenId,
        address quoteTokenAddress,
        address baseTokenAddress,
        bool flipRatio,
        int24 tickLower,
        int24 tickUpper
    ) private pure returns (NFTDescriptor.ConstructTokenURIParams memory params) {
        params.tokenId = tokenId;
        params.quoteTokenAddress = quoteTokenAddress;
        params.baseTokenAddress = baseTokenAddress;
        params.flipRatio = flipRatio;
        params.tickLower = tickLower;
        params.tickUpper = tickUpper;
    }

    /// @dev Creates the second part of the token URI parameters
    function createTokenURIParamsPart2(
        NFTDescriptor.ConstructTokenURIParams memory params,
        int24 tickCurrent,
        int24 tickSpacing,
        uint24 fee,
        address poolAddress
    ) private view returns (NFTDescriptor.ConstructTokenURIParams memory) {
        params.quoteTokenSymbol = getTokenSymbol(params.quoteTokenAddress);
        params.baseTokenSymbol = getTokenSymbol(params.baseTokenAddress);
        params.quoteTokenDecimals = IERC20Metadata(params.quoteTokenAddress).decimals();
        params.baseTokenDecimals = IERC20Metadata(params.baseTokenAddress).decimals();
        params.tickCurrent = tickCurrent;
        params.tickSpacing = tickSpacing;
        params.fee = fee;
        params.poolAddress = poolAddress;
        return params;
    }

    /// @dev Helper function to get token symbol
    function getTokenSymbol(address token) private view returns (string memory) {
        return token == WETH9 ? nativeCurrencyLabel() : SafeERC20Namer.tokenSymbol(token);
    }

    /// @dev Determines if the token pair should be flipped based on priority
    function _flipRatio(address token0, address token1, uint256 chainId) public view returns (bool) {
        return tokenRatioPriority(token0, chainId) > tokenRatioPriority(token1, chainId);
    }

    /// @dev Returns the priority of a token for sorting
    function tokenRatioPriority(address token, uint256 chainId) public view returns (int256) {
        if (token == WETH9) {
            return TokenRatioSortOrder.DENOMINATOR;
        }
        if (chainId == 1) {
            if (token == USDC) {
                return TokenRatioSortOrder.NUMERATOR_MOST;
            } else if (token == USDT) {
                return TokenRatioSortOrder.NUMERATOR_MORE;
            } else if (token == DAI) {
                return TokenRatioSortOrder.NUMERATOR;
            } else if (token == TBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MORE;
            } else if (token == WBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MOST;
            } else {
                return 0;
            }
        }
        return 0;
    }
}
