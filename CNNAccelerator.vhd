LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity CNNAccelerator is
    Port ( 
        CLOCK_50 				: 	in 	std_logic;
		  CLOCK2_50				: 	in 	std_logic;
		  CLOCK3_50				: 	in 	std_logic;
		  CLOCK4_50				: 	in 	std_logic;
        KEY		 				:	in 	std_logic_vector(3 downto 0);
		  SW						:	in		std_logic_vector(9 downto 0);
        LEDR	 				: 	out 	std_logic_vector(9 downto 0);
		  -- HEX Displays
		  HEX0					:	out	std_logic_vector(6 downto 0);
		  HEX1					:	out	std_logic_vector(6 downto 0);
		  HEX2					:	out	std_logic_vector(6 downto 0);
		  HEX3					:	out	std_logic_vector(6 downto 0);
		  HEX4					:	out	std_logic_vector(6 downto 0);
		  HEX5					:	out	std_logic_vector(6 downto 0);
		  -- HPS DDR3 Memory
        HPS_DDR3_ADDR      : 	out   	std_logic_vector(12 downto 0);
        HPS_DDR3_BA        : 	out   	std_logic_vector(2 downto 0);
        HPS_DDR3_CK_P      : 	out   	std_logic;
        HPS_DDR3_CK_N      : 	out   	std_logic;
        HPS_DDR3_CKE       : 	out   	std_logic;
        HPS_DDR3_CS_N      : 	out   	std_logic;
        HPS_DDR3_RAS_N     : 	out   	std_logic;
        HPS_DDR3_CAS_N     : 	out   	std_logic;
        HPS_DDR3_WE_N      : 	out   	std_logic;
        HPS_DDR3_RESET_N   : 	out   	std_logic;
        HPS_DDR3_DQ        : 	inout 	std_logic_vector(7 downto 0);
        HPS_DDR3_DQS_P     : 	inout 	std_logic;
        HPS_DDR3_DQS_N     : 	inout 	std_logic;
        HPS_DDR3_ODT       : 	out   	std_logic;
        HPS_DDR3_DM        : 	out   	std_logic;
        HPS_DDR3_RZQ       : 	in    	std_logic;
        -- HPS I/O (Ethernet, SD Card, USB, UART, I2C)
        HPS_ENET_GTX_CLK   : 	out   	std_logic;
        HPS_ENET_TX_DATA   : 	out   	std_logic_vector(3 downto 0);
        HPS_ENET_RX_CLK    : 	in    	std_logic;
        HPS_ENET_RX_DATA   : 	in    	std_logic_vector(3 downto 0);
        HPS_ENET_MDIO      : 	inout 	std_logic;
        HPS_ENET_MDC       : 	out   	std_logic;
        HPS_ENET_RX_DV     : 	in    	std_logic;
        HPS_ENET_TX_EN     : 	out   	std_logic;
        HPS_SD_CMD         : 	inout 	std_logic;
        HPS_SD_CLK         : 	out   	std_logic;
        HPS_SD_DATA        : 	inout 	std_logic_vector(3 downto 0);
        HPS_USB_CLKOUT     : 	in    	std_logic;
        HPS_USB_DATA       : 	inout 	std_logic_vector(7 downto 0);
        HPS_USB_DIR        : 	in    	std_logic;
        HPS_USB_NXT        : 	in    	std_logic;
        HPS_USB_STP        : 	out   	std_logic;
        HPS_UART_RX        : 	in    	std_logic;
        HPS_UART_TX        : 	out   	std_logic;
        HPS_I2C1_SCLK      : 	inout 	std_logic;
        HPS_I2C1_SDAT      : 	inout 	std_logic
    );
end CNNAccelerator;

architecture arch of CNNAccelerator is

	constant step_val					:	integer								:= 500000;
	signal	counter					:	unsigned(9 downto 0) 			:= (others => '0');
	signal	step_down				:	unsigned(31 downto 0)			:= (others => '0');
	signal	step_latch				:	std_logic							:= '0';
	signal	ocm_address       	:  std_logic_vector(15 downto 0) 	:= (others => '0');
	signal	ocm_chipselect			:  std_logic                    	:= '0';
	signal	ocm_write         	:  std_logic                    	:= '0';
	signal	ocm_readdata      	:  std_logic_vector(31 downto 0)	:= (others => '0');
	signal	ocm_writedata     	:  std_logic_vector(31 downto 0)	:= (others => '0');
	signal	ocm_byteenable    	:  std_logic_vector(3 downto 0) 	:= (others => '0');
	signal	yolo_result				:	std_logic_vector(31 downto 0)	:= (others => '0');
	signal 	yolo_valid_flag 			: std_logic := '0';

-- Component Declaration
	component system is
        port (
            clk_clk                         : in    std_logic                     := 'X';             -- clk
            global_reset_reset_n            : in    std_logic                     := 'X';             -- reset_n
            hps_io_hps_io_emac1_inst_TX_CLK : out   std_logic;                                        -- hps_io_emac1_inst_TX_CLK
            hps_io_hps_io_emac1_inst_TXD0   : out   std_logic;                                        -- hps_io_emac1_inst_TXD0
            hps_io_hps_io_emac1_inst_TXD1   : out   std_logic;                                        -- hps_io_emac1_inst_TXD1
            hps_io_hps_io_emac1_inst_TXD2   : out   std_logic;                                        -- hps_io_emac1_inst_TXD2
            hps_io_hps_io_emac1_inst_TXD3   : out   std_logic;                                        -- hps_io_emac1_inst_TXD3
            hps_io_hps_io_emac1_inst_RXD0   : in    std_logic                     := 'X';             -- hps_io_emac1_inst_RXD0
            hps_io_hps_io_emac1_inst_MDIO   : inout std_logic                     := 'X';             -- hps_io_emac1_inst_MDIO
            hps_io_hps_io_emac1_inst_MDC    : out   std_logic;                                        -- hps_io_emac1_inst_MDC
            hps_io_hps_io_emac1_inst_RX_CTL : in    std_logic                     := 'X';             -- hps_io_emac1_inst_RX_CTL
            hps_io_hps_io_emac1_inst_TX_CTL : out   std_logic;                                        -- hps_io_emac1_inst_TX_CTL
            hps_io_hps_io_emac1_inst_RX_CLK : in    std_logic                     := 'X';             -- hps_io_emac1_inst_RX_CLK
            hps_io_hps_io_emac1_inst_RXD1   : in    std_logic                     := 'X';             -- hps_io_emac1_inst_RXD1
            hps_io_hps_io_emac1_inst_RXD2   : in    std_logic                     := 'X';             -- hps_io_emac1_inst_RXD2
            hps_io_hps_io_emac1_inst_RXD3   : in    std_logic                     := 'X';             -- hps_io_emac1_inst_RXD3
            hps_io_hps_io_sdio_inst_CMD     : inout std_logic                     := 'X';             -- hps_io_sdio_inst_CMD
            hps_io_hps_io_sdio_inst_D0      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D0
            hps_io_hps_io_sdio_inst_D1      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D1
            hps_io_hps_io_sdio_inst_CLK     : out   std_logic;                                        -- hps_io_sdio_inst_CLK
            hps_io_hps_io_sdio_inst_D2      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D2
            hps_io_hps_io_sdio_inst_D3      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D3
            hps_io_hps_io_usb1_inst_D0      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D0
            hps_io_hps_io_usb1_inst_D1      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D1
            hps_io_hps_io_usb1_inst_D2      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D2
            hps_io_hps_io_usb1_inst_D3      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D3
            hps_io_hps_io_usb1_inst_D4      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D4
            hps_io_hps_io_usb1_inst_D5      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D5
            hps_io_hps_io_usb1_inst_D6      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D6
            hps_io_hps_io_usb1_inst_D7      : inout std_logic                     := 'X';             -- hps_io_usb1_inst_D7
            hps_io_hps_io_usb1_inst_CLK     : in    std_logic                     := 'X';             -- hps_io_usb1_inst_CLK
            hps_io_hps_io_usb1_inst_STP     : out   std_logic;                                        -- hps_io_usb1_inst_STP
            hps_io_hps_io_usb1_inst_DIR     : in    std_logic                     := 'X';             -- hps_io_usb1_inst_DIR
            hps_io_hps_io_usb1_inst_NXT     : in    std_logic                     := 'X';             -- hps_io_usb1_inst_NXT
            hps_io_hps_io_uart0_inst_RX     : in    std_logic                     := 'X';             -- hps_io_uart0_inst_RX
            hps_io_hps_io_uart0_inst_TX     : out   std_logic;                                        -- hps_io_uart0_inst_TX
            hps_io_hps_io_i2c1_inst_SDA     : inout std_logic                     := 'X';             -- hps_io_i2c1_inst_SDA
            hps_io_hps_io_i2c1_inst_SCL     : inout std_logic                     := 'X';             -- hps_io_i2c1_inst_SCL
            memory_mem_a                    : out   std_logic_vector(12 downto 0);                    -- mem_a
            memory_mem_ba                   : out   std_logic_vector(2 downto 0);                     -- mem_ba
            memory_mem_ck                   : out   std_logic;                                        -- mem_ck
            memory_mem_ck_n                 : out   std_logic;                                        -- mem_ck_n
            memory_mem_cke                  : out   std_logic;                                        -- mem_cke
            memory_mem_cs_n                 : out   std_logic;                                        -- mem_cs_n
            memory_mem_ras_n                : out   std_logic;                                        -- mem_ras_n
            memory_mem_cas_n                : out   std_logic;                                        -- mem_cas_n
            memory_mem_we_n                 : out   std_logic;                                        -- mem_we_n
            memory_mem_reset_n              : out   std_logic;                                        -- mem_reset_n
            memory_mem_dq                   : inout std_logic_vector(7 downto 0)  := (others => 'X'); -- mem_dq
            memory_mem_dqs                  : inout std_logic                     := 'X';             -- mem_dqs
            memory_mem_dqs_n                : inout std_logic                     := 'X';             -- mem_dqs_n
            memory_mem_odt                  : out   std_logic;                                        -- mem_odt
            memory_mem_dm                   : out   std_logic;                                        -- mem_dm
            memory_oct_rzqin                : in    std_logic                     := 'X';             -- oct_rzqin
            ocm_s2_address                  : in    std_logic_vector(15 downto 0)  := (others => 'X'); -- address
            ocm_s2_chipselect               : in    std_logic                     := 'X';             -- chipselect
            ocm_s2_clken                    : in    std_logic                     := 'X';             -- clken
            ocm_s2_write                    : in    std_logic                     := 'X';             -- write
            ocm_s2_readdata                 : out   std_logic_vector(31 downto 0);                    -- readdata
            ocm_s2_writedata                : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            ocm_s2_byteenable               : in    std_logic_vector(3 downto 0)  := (others => 'X'); -- byteenable
				reset_reset_n                   : in    std_logic                     := 'X'              -- reset_n
        );
    end component system;
	 
	component yolo_core is
        Port ( 
            clk             : in  std_logic;
            reset_n         : in  std_logic;
            mem_address     : out std_logic_vector(15 downto 0);
            mem_read        : out std_logic;
            mem_readdata    : in  std_logic_vector(31 downto 0);
            mem_write       : out std_logic;
            mem_writedata   : out std_logic_vector(31 downto 0);
            yolo_out        : out std_logic_vector(31 downto 0);
            yolo_valid      : out std_logic
        );
    end component yolo_core;

	begin
	 
		u0 : component system
        port map (
            clk_clk                         => CLOCK_50,
            global_reset_reset_n            => KEY(0),
            reset_reset_n                   => KEY(0),
            
            -- Ethernet
            hps_io_hps_io_emac1_inst_TX_CLK => HPS_ENET_GTX_CLK,
            hps_io_hps_io_emac1_inst_TXD0   => HPS_ENET_TX_DATA(0),
            hps_io_hps_io_emac1_inst_TXD1   => HPS_ENET_TX_DATA(1),
            hps_io_hps_io_emac1_inst_TXD2   => HPS_ENET_TX_DATA(2),
            hps_io_hps_io_emac1_inst_TXD3   => HPS_ENET_TX_DATA(3),
            hps_io_hps_io_emac1_inst_RXD0   => HPS_ENET_RX_DATA(0),
            hps_io_hps_io_emac1_inst_RXD1   => HPS_ENET_RX_DATA(1),
            hps_io_hps_io_emac1_inst_RXD2   => HPS_ENET_RX_DATA(2),
            hps_io_hps_io_emac1_inst_RXD3   => HPS_ENET_RX_DATA(3),
            hps_io_hps_io_emac1_inst_MDIO   => HPS_ENET_MDIO,
            hps_io_hps_io_emac1_inst_MDC    => HPS_ENET_MDC,
            hps_io_hps_io_emac1_inst_RX_CTL => HPS_ENET_RX_DV,
            hps_io_hps_io_emac1_inst_TX_CTL => HPS_ENET_TX_EN,
            hps_io_hps_io_emac1_inst_RX_CLK => HPS_ENET_RX_CLK,
            
            -- SD Card
            hps_io_hps_io_sdio_inst_CMD     => HPS_SD_CMD,
            hps_io_hps_io_sdio_inst_CLK     => HPS_SD_CLK,
            hps_io_hps_io_sdio_inst_D0      => HPS_SD_DATA(0),
            hps_io_hps_io_sdio_inst_D1      => HPS_SD_DATA(1),
            hps_io_hps_io_sdio_inst_D2      => HPS_SD_DATA(2),
            hps_io_hps_io_sdio_inst_D3      => HPS_SD_DATA(3),
            
            -- USB
            hps_io_hps_io_usb1_inst_D0      => HPS_USB_DATA(0),
            hps_io_hps_io_usb1_inst_D1      => HPS_USB_DATA(1),
            hps_io_hps_io_usb1_inst_D2      => HPS_USB_DATA(2),
            hps_io_hps_io_usb1_inst_D3      => HPS_USB_DATA(3),
            hps_io_hps_io_usb1_inst_D4      => HPS_USB_DATA(4),
            hps_io_hps_io_usb1_inst_D5      => HPS_USB_DATA(5),
            hps_io_hps_io_usb1_inst_D6      => HPS_USB_DATA(6),
            hps_io_hps_io_usb1_inst_D7      => HPS_USB_DATA(7),
            hps_io_hps_io_usb1_inst_CLK     => HPS_USB_CLKOUT,
            hps_io_hps_io_usb1_inst_STP     => HPS_USB_STP,
            hps_io_hps_io_usb1_inst_DIR     => HPS_USB_DIR,
            hps_io_hps_io_usb1_inst_NXT     => HPS_USB_NXT,
            
            -- UART & I2C
            hps_io_hps_io_uart0_inst_RX     => HPS_UART_RX,
            hps_io_hps_io_uart0_inst_TX     => HPS_UART_TX,
            hps_io_hps_io_i2c1_inst_SDA     => HPS_I2C1_SDAT,
            hps_io_hps_io_i2c1_inst_SCL     => HPS_I2C1_SCLK,
            
            -- Memory (DDR3)
            memory_mem_a                    => HPS_DDR3_ADDR,
            memory_mem_ba                   => HPS_DDR3_BA,
            memory_mem_ck                   => HPS_DDR3_CK_P,
            memory_mem_ck_n                 => HPS_DDR3_CK_N,
            memory_mem_cke                  => HPS_DDR3_CKE,
            memory_mem_cs_n                 => HPS_DDR3_CS_N,
            memory_mem_ras_n                => HPS_DDR3_RAS_N,
            memory_mem_cas_n                => HPS_DDR3_CAS_N,
            memory_mem_we_n                 => HPS_DDR3_WE_N,
            memory_mem_reset_n              => HPS_DDR3_RESET_N,
            memory_mem_dq                   => HPS_DDR3_DQ,
            memory_mem_dqs                  => HPS_DDR3_DQS_P,
            memory_mem_dqs_n                => HPS_DDR3_DQS_N,
            memory_mem_odt                  => HPS_DDR3_ODT,
            memory_mem_dm                   => HPS_DDR3_DM,
            memory_oct_rzqin                => HPS_DDR3_RZQ,
				
				-- OCM
				ocm_s2_address                  => ocm_address,                 
            ocm_s2_chipselect               => ocm_chipselect,             
            ocm_s2_clken                    => '1',                   
            ocm_s2_write                    => ocm_write,                   
            ocm_s2_readdata                 => ocm_readdata,                
            ocm_s2_writedata                => ocm_writedata,               
            ocm_s2_byteenable               => ocm_byteenable               
        );
		  
		yolo_inst : component yolo_core
        port map (
            clk             => CLOCK_50,
            reset_n         => KEY(0),
            
            -- Memory Interface
            mem_address     => ocm_address,
            mem_read        => open,             -- Qsys OCM chipselect acts as the read enable
            mem_readdata    => ocm_readdata,
            mem_write       => ocm_write,        -- Drives the Qsys OCM write enable
            mem_writedata   => ocm_writedata,    -- Drives the Qsys OCM write data bus
            
            -- Output Datapath
            yolo_out        => yolo_result,
            yolo_valid      => yolo_valid_flag
        );
    
	 -- Asynchronous Ties
	 LEDR			<=	std_logic_vector(counter);
	 
	 -- Step down the 50MHz clock to make the blink easier to see
	 step_process	:	process(CLOCK_50)
	 begin
	 
		if (rising_edge(CLOCK_50)) then
			if (step_down = step_val) then
				step_down <= to_unsigned(0, step_down'length);
			else
				step_down <= step_down + 1;
			end if;
		end if;
	 end process step_process;
	 
	 -- Blink LEDs
	 blink_led		: 	process (CLOCK_50)
    begin
        
			if (rising_edge(CLOCK_50)) then
				if (step_down = 0) then
					if (step_latch = '0') then
						counter 		<= counter + 1;
						step_latch	<= '1';
					end if;
				else
					step_latch <= '0';
				end if;
			end if;		  
    end process blink_led;
	 
	 -- Process to decode a 4-bit nibble into a 7-segment display
    hex_display	:	process(ocm_readdata)
        -- Helper function for the decoder
        function decode_hex(nibble : std_logic_vector(3 downto 0)) return std_logic_vector is
        begin
            case nibble is
                when x"0" => return "1000000"; -- 0
                when x"1" => return "1111001"; -- 1
                when x"2" => return "0100100"; -- 2
                when x"3" => return "0110000"; -- 3
                when x"4" => return "0011001"; -- 4
                when x"5" => return "0010010"; -- 5
                when x"6" => return "0000010"; -- 6
                when x"7" => return "1111000"; -- 7
                when x"8" => return "0000000"; -- 8
                when x"9" => return "0010000"; -- 9
                when x"A" => return "0001000"; -- A
                when x"B" => return "0000011"; -- b
                when x"C" => return "1000110"; -- C
                when x"D" => return "0100001"; -- d
                when x"E" => return "0000110"; -- E
                when x"F" => return "0001110"; -- F
                when others => return "1111111"; -- Blank
            end case;
        end function;
    begin
        -- Map the lower 16 bits of the YOLO pipeline result to the 4 HEX displays
        HEX0 <= decode_hex(yolo_result(3 downto 0));
        HEX1 <= decode_hex(yolo_result(7 downto 4));
        HEX2 <= decode_hex(yolo_result(11 downto 8));
        HEX3 <= decode_hex(yolo_result(15 downto 12));
    end process;

    -- Concurrent assignments for OCM control
    ocm_chipselect <= '1';
    ocm_byteenable <= (others => '1');
	 
end arch;