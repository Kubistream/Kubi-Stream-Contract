// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/KubiStreamerDonation.sol";
import "../contracts/interfaces/IERC20.sol";
import "../contracts/interfaces/IYieldWrapper.sol";
import "../contracts/interfaces/IUniswapV3SwapRouter.sol";

// ───────────────────────────────────────────────
// Dummy token for testing
// ───────────────────────────────────────────────
contract MockERC20 is IERC20 {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(uint256 supply) {
        _mint(msg.sender, supply);
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }
}

// ───────────────────────────────────────────────
// Mock Uniswap router (no real pricing)
// ───────────────────────────────────────────────
contract MockFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) pools;

    function getPool(address a, address b, uint24 fee) external view returns (address) {
        return pools[a][b][fee];
    }

    function setPool(address a, address b, uint24 fee, address pool) external {
        pools[a][b][fee] = pool;
        pools[b][a][fee] = pool;
    }
}

contract MockRouter is IUniswapV3SwapRouter {
    address public immutable override WETH9;
    MockFactory public immutable f;

    constructor(address _weth, address _factory) {
        WETH9 = _weth;
        f = MockFactory(_factory);
    }

    function factory() external view override returns (address) {
        return address(f);
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        if (msg.value > 0) {
            require(params.tokenIn == WETH9, "ETH_INPUT_REQUIRES_WETH");
            require(msg.value == params.amountIn, "MISMATCH_MSG_VALUE");
        } else {
            require(
                IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn), "ROUTER_PULL_FAIL"
            );
        }

        require(IERC20(params.tokenOut).transfer(params.recipient, params.amountIn), "ROUTER_SEND_FAIL");
        amountOut = params.amountIn;
    }

    receive() external payable {}
}

// ───────────────────────────────────────────────
// Mock yield token implementing simple mint logic
// ───────────────────────────────────────────────
contract MockYieldToken is IERC20, IYieldWrapper {
    string public name = "MockYield";
    string public symbol = "MYIELD";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    IERC20 public immutable underlyingToken;
    address public owner;
    address public depositor;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DepositorUpdated(address indexed newDepositor);

    constructor(IERC20 _underlying) {
        underlyingToken = _underlying;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    function underlying() external view override returns (address) {
        return address(underlyingToken);
    }

    function setDepositor(address _depositor) external onlyOwner {
        depositor = _depositor;
        emit DepositorUpdated(_depositor);
    }

    function depositYield(address user, uint256 amount) external override {
        require(msg.sender == depositor, "NOT_DEPOSITOR");
        require(amount > 0, "INVALID_AMOUNT");
        require(underlyingToken.transferFrom(msg.sender, address(this), amount), "TRANSFER_FAIL");
        balanceOf[user] += amount;
        totalSupply += amount;
        emit Transfer(address(0), user, amount);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
}

// ───────────────────────────────────────────────
// Test contract
// ───────────────────────────────────────────────
contract KubiStreamerDonationTest is Test {
    KubiStreamerDonation donation;
    MockERC20 tokenA; // ERC20 token
    MockERC20 tokenB; // primary token / vault underlying
    MockERC20 tokenC; // extra token
    MockYieldToken yieldTokenB;
    MockYieldToken yieldTokenA;
    MockRouter router;
    MockFactory factory;
    address superAdmin = address(0xAAA);
    address feeRecipient = address(0xFEE);
    address streamer = address(0xBEEF);
    address donor = address(0xCAFE);
    address weth = makeAddr("WETH");
    uint24 constant POOL_FEE = 3_000;

    function setUp() public {
        factory = new MockFactory();
        router = new MockRouter(weth, address(factory));

        tokenA = new MockERC20(2_000_000 ether);
        tokenB = new MockERC20(1_000_000 ether);
        tokenC = new MockERC20(1_000_000 ether);
        yieldTokenB = new MockYieldToken(IERC20(address(tokenB)));
        yieldTokenA = new MockYieldToken(IERC20(address(tokenA)));

        tokenA.approve(address(router), type(uint256).max);
        require(tokenA.transfer(address(router), 500_000 ether), "FUND_ROUTER_A");
        require(tokenB.transfer(address(router), 1_000_000 ether), "FUND_ROUTER_B");

        donation = new KubiStreamerDonation(address(router), superAdmin, 250, feeRecipient);
        yieldTokenB.setDepositor(address(donation));
        yieldTokenA.setDepositor(address(donation));

        factory.setPool(address(tokenA), address(tokenB), POOL_FEE, address(0x1));
        factory.setPool(address(tokenB), weth, POOL_FEE, address(0x2));
        factory.setPool(address(tokenA), weth, POOL_FEE, address(0x4));
        factory.setPool(address(tokenC), address(tokenA), POOL_FEE, address(0x3));

        require(tokenA.transfer(donor, 10_000 ether), "FUND_DONOR_A");
        require(tokenC.transfer(donor, 10_000 ether), "FUND_DONOR_C");
        vm.deal(donor, 100 ether);

        vm.startPrank(superAdmin);
        donation.setGlobalWhitelist(address(tokenA), true);
        donation.setGlobalWhitelist(address(tokenB), true);
        donation.setGlobalWhitelist(address(tokenC), true);
        donation.setGlobalWhitelist(address(0), true); // ETH
        donation.setPoolFee(address(tokenA), address(tokenB), POOL_FEE);
        donation.setPoolFee(address(tokenC), address(tokenA), POOL_FEE);
        donation.setPoolFee(address(0), address(tokenB), POOL_FEE);
        donation.setPoolFee(address(0), address(tokenA), POOL_FEE);
        vm.stopPrank();
    }

    function testDonateERC20_Direct() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenA), true);
        donation.setStreamerWhitelist(streamer, address(tokenC), true);
        donation.setPrimaryToken(streamer, address(tokenA));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
    }

    function testDonateERC20_AutoSwap() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
    }

    function testDonateETH_Direct() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(0), true);
        vm.stopPrank();

        uint256 balanceBefore = streamer.balance;
        vm.prank(donor);
        donation.donate{value: 1 ether}(donor, address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(streamer.balance - balanceBefore, 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }

    function testDonateETH_AutoSwap() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();

        vm.prank(donor);
        donation.donate{value: 1 ether}(donor, address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(tokenB.balanceOf(streamer), 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }

    function testDonateERC20_Yield() public {
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldTokenB), address(tokenB), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldTokenB));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(yieldTokenB.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
        assertEq(tokenB.balanceOf(address(yieldTokenB)), 97.5 ether);
    }

    function testDonateETH_Yield() public {
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldTokenB), address(tokenB), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldTokenB));
        vm.stopPrank();

        vm.prank(donor);
        donation.donate{value: 1 ether}(donor, address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(yieldTokenB.balanceOf(streamer), 0.975 ether);
        assertEq(tokenB.balanceOf(address(yieldTokenB)), 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }

    function testRemoveYieldByContract() public {
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldTokenB), address(tokenB), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldTokenB));
        donation.setStreamerActiveYield(streamer, address(yieldTokenB));
        donation.removeStreamerYieldContract(streamer, address(yieldTokenB));
        vm.stopPrank();

        assertEq(donation.getStreamerYield(streamer, address(tokenB)), address(0));
        (address activeYield,) = donation.getStreamerActiveYield(streamer);
        assertEq(activeYield, address(0));
    }

    function testRemoveYieldRevertsWhenNotConfigured() public {
        vm.expectRevert(abi.encodeWithSelector(YieldNotConfigured.selector));
        vm.prank(superAdmin);
        donation.removeStreamerYieldContract(streamer, address(yieldTokenB));
    }

    function testSetActiveYieldAndClear() public {
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldTokenB), address(tokenB), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldTokenB));
        donation.setStreamerActiveYield(streamer, address(yieldTokenB));
        vm.stopPrank();

        (address activeYield, address activeUnderlying) = donation.getStreamerActiveYield(streamer);
        assertEq(activeYield, address(yieldTokenB));
        assertEq(activeUnderlying, address(tokenB));

        vm.prank(superAdmin);
        donation.setStreamerActiveYield(streamer, address(0));

        (activeYield, activeUnderlying) = donation.getStreamerActiveYield(streamer);
        assertEq(activeYield, address(0));
        assertEq(activeUnderlying, address(0));
    }

    function testSetActiveYieldRevertsIfNotConfigured() public {
        vm.expectRevert(abi.encodeWithSelector(YieldContractNotWhitelisted.selector));
        vm.prank(superAdmin);
        donation.setStreamerActiveYield(streamer, address(yieldTokenA));
    }

    function testDonateBelowMinSkipsYield() public {
        vm.expectRevert(abi.encodeWithSelector(YieldNotConfigured.selector));
        vm.prank(superAdmin);
        donation.removeStreamerYieldContract(streamer, address(yieldTokenA));
    }

    function testDonateUsesActiveYieldFallback() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenA), true);
        donation.setPrimaryToken(streamer, address(tokenA));
        donation.setYieldConfig(address(yieldTokenA), address(tokenA), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldTokenA));
        donation.setStreamerActiveYield(streamer, address(yieldTokenA));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenC.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenC), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(yieldTokenA.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(address(yieldTokenA)), 97.5 ether);
    }
}
