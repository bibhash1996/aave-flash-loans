pragma solidity ^0.6.6;

import "./aave/FlashLoanReceiverBase.sol";
import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/ILendingPool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract Flashloan is FlashLoanReceiverBase {
    ISwapRouter iSwapRouter;
    address constant ROUTER_ADDRESS =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WETH9 = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;

    constructor(address _addressProvider)
        public
        FlashLoanReceiverBase(_addressProvider)
    {
        iSwapRouter = ISwapRouter(ROUTER_ADDRESS);
    }

    // Swaps to the exact DAI given in the input. The amount of ETH to be deducted is calculated accordingly.
    function convertEthToExactDai(uint256 daiAmount) external payable {
        require(daiAmount > 0, "Must pass non 0 DAI amount");
        require(msg.value > 0, "Must pass non 0 ETH amount");

        uint256 deadline = block.timestamp + 15; // using 'now' for convenience, for mainnet pass deadline from frontend!
        address tokenIn = WETH9;
        address tokenOut = DAI;
        uint24 fee = 3000;
        address recipient = msg.sender;
        uint256 amountOut = daiAmount;
        uint256 amountInMaximum = msg.value;
        uint160 sqrtPriceLimitX96 = 0;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams(
                tokenIn,
                tokenOut,
                fee,
                recipient,
                deadline,
                amountOut,
                amountInMaximum,
                sqrtPriceLimitX96
            );

        uniswapRouter.exactOutputSingle{value: msg.value}(params);
        uniswapRouter.refundETH();

        // refund leftover ETH to user
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    function convertExactEthToDai() external payable {
        require(msg.value > 0, "Must pass non 0 ETH amount");

        uint256 deadline = block.timestamp + 15;
        address tokenIn = WETH9;
        address tokenOut = DAI;
        uint24 fee = 3000;
        address recipient = msg.sender;
        uint256 amountIn = msg.value;
        uint256 amountOutMinimum = 1;
        uint160 sqrtPriceLimitX96 = 0;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                tokenIn,
                tokenOut,
                fee,
                recipient,
                deadline,
                amountIn,
                amountOutMinimum,
                sqrtPriceLimitX96
            );

        uniswapRouter.exactInputSingle{value: msg.value}(params);
        uniswapRouter.refundETH();

        // refund leftover ETH to user
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        require(
            _amount <= getBalanceInternal(address(this), _reserve),
            "Invalid balance, was the flashLoan successful?"
        );

        //
        // Your logic goes here.
        // !! Ensure that *this contract* has enough of `_reserve` funds to payback the `_fee` !!
        //

        uint256 totalDebt = _amount.add(_fee);
        transferFundsBackToPoolInternal(_reserve, totalDebt);
    }

    /**
        Flash loan 1000000000000000000 wei (1 ether) worth of `_asset`
     */
    function flashloan(address _asset, uint256 _amount) public onlyOwner {
        bytes memory data = "";
        // uint256 amount = 1 ether;

        ILendingPool lendingPool = ILendingPool(
            addressesProvider.getLendingPool()
        );
        lendingPool.flashLoan(address(this), _asset, _amount, data);
    }

    receive() external payable {}
}
