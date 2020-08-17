pragma solidity 0.4.17;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
  function mul(uint256 a, uint256 b) internal view returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal view returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal view returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal view returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

 
// contract Token {
//         function transfer(address to, uint256 value) public constant returns (bool success) ;
//         function transferFrom(address from, address to, uint256 value) public constant returns (bool success) ;
//     }
interface Token {
    function totalSupply() public constant returns (uint);
    function balanceOf(address tokenOwner) public constant returns (uint balance);
    function allowance(address tokenOwner, address spender) public constant returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}
contract exchange{

   using SafeMath for uint256;
   address public base_coin_addr; //base , erc721
   address public quote_coin_addr; //quote, erc20
   mapping(address => mapping(address=> uint256)) public normal_balances ;  // coin_addr => owner_addr => amount
   mapping(address => mapping(address=> uint256)) public freeze_balances;  // coin_addr => owner_addr => amount
   uint  public buy_order_amount ;
   uint  public sell_order_amount ;
   uint public fee_amount_per=1;
   uint public all_fee_income;
  struct Order
  {
      uint order_id;
      string side;
      address  user_addr;
      uint256 price;
      uint256 volume;
      uint256 matched_volume;
      uint8 status; //0 init,1 : all matched,2 part matched
  }
  mapping(uint => Order[]) public sell_orders; // price => Order
  mapping(uint => Order[]) public buy_orders; // price => Order
  uint[] public all_sell_price;
   modifier is_support_coin(address coin_addr) {
    require(coin_addr==base_coin_addr || coin_addr==quote_coin_addr);
    _;
  }
 
 
  modifier is_support_side(string memory side) {
    require(keccak256(side)==keccak256("BUY") || keccak256(side)==keccak256("SELL"));
    _;
  }
   //add coin pairs

   //erc20相当于usdt
   function exchange(address add_erc20, address add_erc721) public
   {
       base_coin_addr=add_erc20;
       quote_coin_addr=add_erc721;
   }
   // deposit
   function deposit(address coin_addr, uint amount ) is_support_coin(coin_addr)  public {
       
    // need approve first
    if (!Token(coin_addr).transferFrom(msg.sender,this, amount)) revert();
      //add balance in exchange
      //transferFrom 
    normal_balances[coin_addr][msg.sender]= normal_balances[coin_addr][msg.sender].add(amount);
   
  }
    
     //withdraw can choose token 
   function withdraw(address coin_addr, uint amount ) is_support_coin(coin_addr) public {
    require(normal_balances[coin_addr][msg.sender]>=amount);
    
     //sub balance in exchange
    normal_balances[coin_addr][msg.sender]=normal_balances[coin_addr][msg.sender].sub(amount);
        //transfer to owner
    Token(coin_addr).transfer(msg.sender, amount);
   }
    //"SELL"
    function sell(address coin_addr,string memory side,uint volume,uint price)  is_support_coin(coin_addr) public
    {
        require(keccak256(side)==keccak256("SELL"));
        make_order(coin_addr,side,volume,price);
    } 
    
    //buy 
    function buy(address coin_addr,string  side,uint volume,uint buy_price) is_support_side(side) is_support_coin(coin_addr) public
    {
        require(keccak256(side)==keccak256("BUY"));
        uint buyer_order_index=make_order(coin_addr,side,volume,buy_price);
        
        // match
        uint matched_amount=0;
        bool finished_match=false;
        for (uint i=0;i<sell_order_amount;i++)
        {
            uint price=all_sell_price[i];
            if(buy_price>=price)
            {
                uint  still_need_match_volume; //还需要的
                
                for (uint j=0;j<sell_orders[price].length;j++)
                {
                    Order memory  ord = sell_orders[price][j];
                    still_need_match_volume=volume-matched_amount;
                    uint remain_volume=ord.volume-ord.matched_volume;  //left amount of this sell order 
                    if (still_need_match_volume==0)  //finished match
                    {
                        return;
                    }
                    
                    if (ord.status==1) //had  finished orders
                    {
                        continue;
                    }
                    
                    if(remain_volume!=0)   //can match
                    {
                        
                        //part macthed to buy order 
                        if (still_need_match_volume>=remain_volume)
                        {
                                 // add matched amount
                                matched_amount+=remain_volume;
                                // change balance in exchange
                                
                                change_balance_after_match(msg.sender,ord.user_addr,remain_volume);
                               
                                //set sell order's status
                                sell_orders[price][j].matched_volume=sell_orders[price][j].volume;
                                //set to all matched
                                sell_orders[price][j].status=1;
                                
                                //take fee from seller 
                                if (remain_volume>=fee_amount_per)
                                {
                                    all_fee_income+=fee_amount_per;
                                    normal_balances[quote_coin_addr][this]=normal_balances[quote_coin_addr][this].add(fee_amount_per);
                                    normal_balances[quote_coin_addr][ord.user_addr]=normal_balances[quote_coin_addr][ord.user_addr].sub(fee_amount_per);
                                }
                               
                        }
                        //all macted 
                        else if (still_need_match_volume< remain_volume)
                        {
                                // add matched amount
                                matched_amount=volume;
                                
                                change_balance_after_match(msg.sender,ord.user_addr,still_need_match_volume);
                                
                                //set sell order's status
                                sell_orders[price][j].matched_volume=sell_orders[price][j].matched_volume.add(still_need_match_volume);
                                //set to seller's order matched
                                sell_orders[price][j].status=2;
                                
                                
                                //finish buyer's order
                                finished_match=true;
                                break;
                        }
                        

                    }
                }
               
            }
            //check whether finished 
            if (finished_match)
            {
                break;
            }
        }
        //set buyer's order status
        if (matched_amount==0)
        {
             buy_orders[buy_price][buyer_order_index].status=0;
        }
        else if (matched_amount==volume)
        {
            buy_orders[buy_price][buyer_order_index].status=1;
            buy_orders[buy_price][buyer_order_index].matched_volume=volume;
        }
        else
        {
            buy_orders[buy_price][buyer_order_index].status=2;
            buy_orders[buy_price][buyer_order_index].matched_volume=matched_amount;
        }
        
       
        
    } 
    
    function change_balance_after_match(address buyer_addr,address seller_addr,uint order_amount) internal
    {
        //add buyer's normal erc721
         normal_balances[base_coin_addr][buyer_addr]=normal_balances[base_coin_addr][buyer_addr].add(order_amount);
         // 
        //sub buyer's  freeze erc20 
        freeze_balances[quote_coin_addr][buyer_addr]=freeze_balances[quote_coin_addr][buyer_addr].sub(order_amount);
        
        
        //add seller's  normal erc20 
        normal_balances[quote_coin_addr][seller_addr]=freeze_balances[quote_coin_addr][seller_addr].add(order_amount);
        
        //sub sell's freezed erc721
        freeze_balances[base_coin_addr][seller_addr]=freeze_balances[base_coin_addr][seller_addr].sub(order_amount);
    }


    function make_order(address coin_addr,string memory side,uint volume,uint price)  is_support_side(side) is_support_coin(coin_addr)  internal returns(uint order_index)
    {
        // freeze normal balance before make Order
        if (keccak256(side)==keccak256("SELL")) //sub erc721 balance
        {
            require(volume<=normal_balances[base_coin_addr][msg.sender]);
         //sub normal balance 721
            normal_balances[base_coin_addr][msg.sender]=normal_balances[base_coin_addr][msg.sender].sub(volume);
        // add freeze_balances 721
             freeze_balances[base_coin_addr][msg.sender]=freeze_balances[base_coin_addr][msg.sender].add(volume);
         //make Order
            sell_orders[price].push(Order(sell_order_amount, side,msg.sender,price,volume,0,0));
        all_sell_price.push(price);
        sell_order_amount+=1;
        return sell_orders[price].length-1;
        }
        else if (keccak256(side)==keccak256("BUY"))
        {
              require(volume*price <=normal_balances[quote_coin_addr][msg.sender]);
            //sub normal balance erc20 
            normal_balances[quote_coin_addr][msg.sender]=normal_balances[quote_coin_addr][msg.sender].sub(volume);
            // add freeze_balances erc20 
             freeze_balances[quote_coin_addr][msg.sender]=freeze_balances[quote_coin_addr][msg.sender].add(volume);
                      //make Order
            buy_orders[price].push(Order(buy_order_amount, side,msg.sender,price,volume,0,0));
            buy_order_amount+=1;
            return buy_orders[price].length-1;
        }
        

    }
    function get_base_coin_balance(address addr) public  view returns(uint)   
    {
        return Token(base_coin_addr).balanceOf(addr);
    }
    function get_quote_coin_balance(address addr) public view returns (uint) 
    {
        return Token(quote_coin_addr).balanceOf(addr);
    }
    function get_ex_base_coin_normal_balance(address addr) public view returns (uint) 
    {
        return normal_balances[base_coin_addr][addr];
    }

     function get_ex_quote_coin_normal_balance(address addr) public view returns (uint) 
    {
        return normal_balances[quote_coin_addr][addr];
    }
    
    function get_ex_base_coin_freeze_balance(address addr) public view returns (uint) 
    {
        return freeze_balances[base_coin_addr][addr];
    }

     function get_ex_quote_coin_freeze_balance(address addr) public view returns (uint) 
    {
        return freeze_balances[quote_coin_addr][addr];
    }
  
  
}