//SPDX-License-Identifier: MIT
pragma solidity  0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "../libs/price.sol";

interface IUniRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) ;

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);

}

interface IUniPair is IERC20Upgradeable{
    function getReserves() external view returns (uint, uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IMasterChefV2 {
    function pendingCake(uint pid, address user) external view returns (uint);
    function poolInfo(uint pid) external view returns(uint, uint, uint, uint, bool);
    function userInfo(uint pid, address user) external view returns(uint, uint, uint);
    function lpToken(uint pid) external view returns(address);

    function deposit(uint pid, uint amount) external;
    function withdraw(uint pid, uint amount) external;
}

contract BscVault is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    using SafeERC20Upgradeable for IUniPair;

    IERC20Upgradeable public constant CAKE  = IERC20Upgradeable(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IERC20Upgradeable public constant WBNB = IERC20Upgradeable(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;
    IUniPair public lpToken;

    IUniRouter public constant PckRouter = IUniRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IMasterChefV2 public constant MasterChefV2 = IMasterChefV2(0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652);

    uint constant DENOMINATOR = 10000;
    uint public yieldFee;

    address public treasuryWallet;
    address public admin;

    mapping(address => uint) private depositedBlock;

    uint pid;

    event Deposit(address _user, uint _amount, uint _shares);
    event EmergencyWithdraw(uint _amount);
    event Invest(uint _amount);
    event SetAdmin(address _oldAdmin, address _newAdmin);
    event SetYieldFeePerc(uint _fee);
    event SetTreasuryWallet(address _wallet);
    event Withdraw(address _user, uint _amount, uint _shares);
    event YieldFee(uint _amount);
    event Yield(uint _amount);

    modifier onlyOwnerOrAdmin {
        require(msg.sender == owner() || msg.sender == admin, "Only owner or admin");
        _;
    }


    function initialize(string memory _name, string memory _symbol, 
        uint _pid,
        address _treasury, address _admin
    ) external initializer {

        __ERC20_init(_name, _symbol);
        __Ownable_init();

        yieldFee = 2000; //20%
        pid = _pid;

        address _lpToken = MasterChefV2.lpToken(_pid);

        lpToken = IUniPair(_lpToken);
        token0 = IERC20Upgradeable(lpToken.token0());
        token1 = IERC20Upgradeable(lpToken.token1());
        
        treasuryWallet = _treasury;
        admin = _admin;
        
        lpToken.safeApprove(address(MasterChefV2), type(uint).max);
        CAKE.safeApprove(address(PckRouter), type(uint).max);
        token0.approve(address(PckRouter), type(uint).max);
        token1.approve(address(PckRouter), type(uint).max);
    
    }
    
    /**
     *@param _amount amount of lptokens to deposit
    */
    function deposit(uint _amount) external nonReentrant whenNotPaused{
        require(_amount > 0, "Invalid amount");

        depositedBlock[msg.sender] = block.number;
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint _pool = getAllPool();
        MasterChefV2.deposit(pid, _amount);

        uint _totalSupply = totalSupply();
        uint _shares = _totalSupply == 0 ? _amount : _amount * _totalSupply / _pool;
        _mint(msg.sender, _shares);

        emit Deposit(msg.sender, _amount, _shares);
    }

    /**
     *@param _shares amount of shares to burn
    */
    function withdraw(uint _shares) external nonReentrant{
        require(_shares > 0, "Invalid Amount");
        require(balanceOf(msg.sender) >= _shares, "Not enough balance");
        require(depositedBlock[msg.sender] != block.number, "Withdraw within same block");

        uint _amountToWithdraw = getAllPool() * _shares / totalSupply(); 

        uint lpTokenAvailable = lpToken.balanceOf(address(this));
        if(lpTokenAvailable < _amountToWithdraw) {
            MasterChefV2.withdraw(pid, _amountToWithdraw - lpTokenAvailable );
        }
        _burn(msg.sender, _shares);

        lpToken.safeTransfer(msg.sender, _amountToWithdraw);
        emit Withdraw(msg.sender, _amountToWithdraw, _shares);
    }

    function _invest() private returns (uint available){
        available = lpToken.balanceOf(address(this));
        if(available > 0) {
            MasterChefV2.deposit(pid, available);
        }
    }

    ///@notice Withdraws funds staked in mirror to this vault and pauses deposit, yield, invest functions
    function emergencyWithdraw() external onlyOwnerOrAdmin whenNotPaused{ 
        _pause();
        _yield();
        (uint stakedTokens,,) = MasterChefV2.userInfo(pid, address(this));
        if(stakedTokens > 0 ) {
            MasterChefV2.withdraw(pid, stakedTokens);
        }
        emit EmergencyWithdraw(stakedTokens);
    }

    ///@notice Unpauses deposit, yield, invest functions, and invests funds.
    function reInvest() external onlyOwnerOrAdmin whenPaused {
        _unpause();
        _invest();
    }

    function setAdmin(address _newAdmin) external onlyOwner{
        address oldAdmin = admin;
        admin = _newAdmin;

        emit SetAdmin(oldAdmin, _newAdmin);
    }

    ///@notice Function to set deposit and yield fee
    ///@param _yieldFeePerc deposit fee percentage. 2000 for 20%
    function setFee(uint _yieldFeePerc) external onlyOwner{
        yieldFee = _yieldFeePerc;
        emit SetYieldFeePerc(_yieldFeePerc);
    }

    function setTreasuryWallet(address _wallet) external onlyOwner {
        treasuryWallet = _wallet;
        emit SetTreasuryWallet(_wallet);
    }

    function yield() external onlyOwnerOrAdmin whenNotPaused {
        _yield();
    }

    function _yield() private {
        uint cakeBalance = CAKE.balanceOf(address(this));
        
        if(cakeBalance > 0) {
            uint fee = cakeBalance * yieldFee / DENOMINATOR; //yield fee
            CAKE.safeTransfer(treasuryWallet, fee);
            cakeBalance -= fee;

            uint _token0Amount = token0 == CAKE ? cakeBalance /2 : _swap(address(CAKE), address(token0), cakeBalance/2)[1];
            uint _token1Amount = token1 == CAKE ? cakeBalance /2 :  _swap(address(CAKE), address(token1), cakeBalance/2)[1];

            PckRouter.addLiquidity(address(token0), address(token1), _token0Amount, _token1Amount, 0, 0, address(this), block.timestamp);

            _invest();

            (uint CAKEPriceInUSD, uint denominator) = PriceLib.getCAKEPriceInUSD();
            emit Yield((cakeBalance + fee) * CAKEPriceInUSD / denominator);
            emit YieldFee(fee * CAKEPriceInUSD / denominator);
        }
    }

    function _swap(address _tokenA, address _tokenB, uint _amt) private returns (uint[] memory amounts){
        address[] memory path = new address[](2);

        path[0] = address(_tokenA);
        path[1] = address(_tokenB);

        amounts = PckRouter.swapExactTokensForTokens(_amt, 0, path, address(this), block.timestamp);
    }

    function getAllPool() public view returns (uint ) {
        (uint stakedTokens,,) = MasterChefV2.userInfo(pid, address(this));
        return lpToken.balanceOf(address(this)) + stakedTokens;
    }

    function getAllPoolInBNB() public view returns (uint _valueInBNB) {
        uint _pool = getAllPool();
        uint _totalSupply = lpToken.totalSupply();

        (uint _reserve0, uint _reserve1) = lpToken.getReserves();
        
        uint _total0 = _pool * _reserve0 / _totalSupply;
        uint _total1 = _pool * _reserve1 / _totalSupply;
        
        _valueInBNB = (_total0 * _getPriceInBNB(address(token0))) + 
        (_total1 * _getPriceInBNB(address(token1))) ;

        _valueInBNB = _valueInBNB / 1e18;
    }

    function _getPriceInBNB(address _token) private view returns (uint) {
        if(_token == address(WBNB)) {
            return 1e18;
        } else {
            address[] memory path = new address[](2);

            path[0] = _token;
            path[1] = address(WBNB);
            return PckRouter.getAmountsOut(1e18, path)[1];
        }
    }

    function getAllPoolInUSD() public view returns (uint) {
        (uint BNBPriceInUSD, uint denominator) = PriceLib.getBNBPriceInUSD();
        return getAllPoolInBNB() * BNBPriceInUSD / denominator;
    }

    function getPricePerFullShare(bool inUSD) public view returns (uint) {
        uint _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;
        return inUSD == true ?
            getAllPoolInUSD() * 1e18 / _totalSupply :
            getAllPool() * 1e18 / _totalSupply;
    }

}
