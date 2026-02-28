LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity CNNAccelerator is
    Port ( 
        CLOCK_50 	: 	in 				std_logic;
		  CLOCK2_50	: 	in 				std_logic;
		  CLOCK3_50	: 	in 				std_logic;
		  CLOCK4_50	: 	in 				std_logic;
        KEY		 	:	in 				std_logic_vector(3 downto 0);
		  SW			:	in					std_logic_vector(9 downto 0);
        LEDR	 	: 	out 				std_logic_vector(9 downto 0);
		  -- HPS DDR3 Memory
        HPS_DDR3_ADDR      : out   	std_logic_vector(12 downto 0);
        HPS_DDR3_BA        : out   	std_logic_vector(2 downto 0);
        HPS_DDR3_CK_P      : out   	std_logic;
        HPS_DDR3_CK_N      : out   	std_logic;
        HPS_DDR3_CKE       : out   	std_logic;
        HPS_DDR3_CS_N      : out   	std_logic;
        HPS_DDR3_RAS_N     : out   	std_logic;
        HPS_DDR3_CAS_N     : out   	std_logic;
        HPS_DDR3_WE_N      : out   	std_logic;
        HPS_DDR3_RESET_N   : out   	std_logic;
        HPS_DDR3_DQ        : inout 	std_logic_vector(7 downto 0);
        HPS_DDR3_DQS_P     : inout 	std_logic;
        HPS_DDR3_DQS_N     : inout 	std_logic;
        HPS_DDR3_ODT       : out   	std_logic;
        HPS_DDR3_DM        : out   	std_logic;
        HPS_DDR3_RZQ       : in    	std_logic;
        -- HPS I/O (Ethernet, SD Card, USB, UART, I2C)
        HPS_ENET_GTX_CLK   : out   	std_logic;
        HPS_ENET_TX_DATA   : out   	std_logic_vector(3 downto 0);
        HPS_ENET_RX_CLK    : in    	std_logic;
        HPS_ENET_RX_DATA   : in    	std_logic_vector(3 downto 0);
        HPS_ENET_MDIO      : inout 	std_logic;
        HPS_ENET_MDC       : out   	std_logic;
        HPS_ENET_RX_DV     : in    	std_logic;
        HPS_ENET_TX_EN     : out   	std_logic;
        HPS_SD_CMD         : inout 	std_logic;
        HPS_SD_CLK         : out   	std_logic;
        HPS_SD_DATA        : inout 	std_logic_vector(3 downto 0);
        HPS_USB_CLKOUT     : in    	std_logic;
        HPS_USB_DATA       : inout 	std_logic_vector(7 downto 0);
        HPS_USB_DIR        : in    	std_logic;
        HPS_USB_NXT        : in    	std_logic;
        HPS_USB_STP        : out   	std_logic;
        HPS_UART_RX        : in    	std_logic;
        HPS_UART_TX        : out   	std_logic;
        HPS_I2C1_SCLK      : inout 	std_logic;
        HPS_I2C1_SDAT      : inout 	std_logic
    );
end CNNAccelerator;

architecture arch of CNNAccelerator is

	constant step_val		:	integer						:= 500000;
	signal	counter		:	unsigned(9 downto 0) 	:= (others => '0');
	signal	step_down	:	unsigned(31 downto 0)	:= (others => '0');
	signal	step_latch	:	std_logic					:= '0';

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
            reset_reset_n                   : in    std_logic                     := 'X'              -- reset_n
        );
    end component system;

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
            memory_oct_rzqin                => HPS_DDR3_RZQ
        );
    
	 -- Asynchronous Ties
	 LEDR			<=	std_logic_vector(counter);
	 
	 -- Processes
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
	 
end arch;