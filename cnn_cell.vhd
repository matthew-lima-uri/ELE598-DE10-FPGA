LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- ====================================================================
-- CNN Component Library Package
-- ====================================================================
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

package cnn_pkg is
    -- Data Types
    type window_3x3 is array (0 to 8) of std_logic_vector(15 downto 0);
    type window_2x2_32b is array (0 to 3) of std_logic_vector(31 downto 0);

    -- 1. CNN Cell (MAC + Bias + Activation)
    component cnn_cell is
        Port ( 
            clk             : in  std_logic;
            reset_n         : in  std_logic;
            enable          : in  std_logic;
            data_valid      : in  std_logic;
            first_channel   : in  std_logic;
            last_channel    : in  std_logic;
            out_valid       : out std_logic;
            pixel_window    : in  window_3x3;
            weight_window   : in  window_3x3;
            bias_in         : in  std_logic_vector(31 downto 0);
            conv_out        : out std_logic_vector(31 downto 0)
        );
    end component;

    -- 2. Input Line Buffer (16-bit Pixels)
    component line_buffer is
        Generic ( IMAGE_WIDTH : integer := 416 );
        Port ( 
            clk             : in  std_logic;
            reset_n         : in  std_logic;
            shift_en        : in  std_logic;
            pixel_in        : in  std_logic_vector(15 downto 0);
            window_out      : out window_3x3
        );
    end component;

    -- 3. Max Pooling (2x2)
    component max_pool_2x2 is
        Port ( 
            clk             : in  std_logic;
            reset_n         : in  std_logic;
            enable          : in  std_logic;
            data_valid      : in  std_logic;
            pixel_00        : in  std_logic_vector(31 downto 0);
            pixel_01        : in  std_logic_vector(31 downto 0);
            pixel_10        : in  std_logic_vector(31 downto 0);
            pixel_11        : in  std_logic_vector(31 downto 0);
            out_valid       : out std_logic;
            max_out         : out std_logic_vector(31 downto 0)
        );
    end component;
end package cnn_pkg;

-- ====================================================================
-- Entity: cnn_cell
-- Description: 7-Stage pipelined 3x3 Convolution Cell with Depth 
-- Accumulation, Bias Addition, and Leaky ReLU Activation.
-- ====================================================================
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cnn_pkg.ALL;

entity cnn_cell is
    Port ( 
        clk             : in  std_logic;
        reset_n         : in  std_logic;
        
        enable          : in  std_logic;
        data_valid      : in  std_logic;
        first_channel   : in  std_logic;
        last_channel    : in  std_logic;
        
        out_valid       : out std_logic;
		  mode_1x1 			: in std_logic;
        
        pixel_window    : in  window_3x3;
        weight_window   : in  window_3x3;
        bias_in         : in  std_logic_vector(31 downto 0);
        
        conv_out        : out std_logic_vector(31 downto 0)
    );
end cnn_cell;

architecture rtl of cnn_cell is

    -- Stage 1: Multiplier Array
    type mult_array is array (0 to 8) of signed(31 downto 0);
    signal mult_stage : mult_array := (others => (others => '0'));

    -- Stages 2-5: Spatial Adder Tree
    signal add_stg1_0, add_stg1_1, add_stg1_2, add_stg1_3, add_stg1_4 : signed(31 downto 0) := (others => '0');
    signal add_stg2_0, add_stg2_1, add_stg2_2                         : signed(31 downto 0) := (others => '0');
    signal add_stg3_0, add_stg3_1                                     : signed(31 downto 0) := (others => '0');
    signal spatial_sum                                                : signed(31 downto 0) := (others => '0');
    
    -- Stage 6: Channel Depth Accumulator
    signal chan_accum                                                 : signed(31 downto 0) := (others => '0');
    
    -- Stage 7: Activation Output Register
    signal final_activation                                           : signed(31 downto 0) := (others => '0');
    
    -- Pipeline Shift Registers for Control Signals (Extended to 7 bits)
    signal valid_sr : std_logic_vector(6 downto 0) := (others => '0');
    signal first_sr : std_logic_vector(6 downto 0) := (others => '0');
    signal last_sr  : std_logic_vector(6 downto 0) := (others => '0');

begin

    conv_process : process(clk, reset_n)
        -- Variable utilized for combinatorial logic within Stage 7
        variable v_biased_sum : signed(31 downto 0);
    begin
        if (reset_n = '0') then
            mult_stage       	<= (others => (others => '0'));
            valid_sr         	<= (others => '0');
            first_sr         	<= (others => '0');
            last_sr          	<= (others => '0');
            spatial_sum      	<= (others => '0');
            chan_accum       	<= (others => '0');
            final_activation 	<= (others => '0');
				mode_1x1_sr 		<= (others => '0');
            
        elsif (rising_edge(clk)) then
            if (enable = '1') then
            
                -- Shift Control Signals
                valid_sr 		<= valid_sr(5 downto 0) 	& data_valid;
                first_sr 		<= first_sr(5 downto 0) 	& first_channel;
                last_sr  		<= last_sr(5 downto 0)  	& last_channel;
					 mode_1x1_sr 	<= mode_1x1_sr(5 downto 0) & mode_1x1;
            
                -- STAGE 1: Parallel Multiplication
                for i in 0 to 8 loop
                    mult_stage(i) <= signed(pixel_window(i)) * signed(weight_window(i));
                end loop;

                -- STAGE 2: Adder Tree Level 1
                add_stg1_0 <= mult_stage(0) + mult_stage(1);
                add_stg1_1 <= mult_stage(2) + mult_stage(3);
                add_stg1_2 <= mult_stage(4) + mult_stage(5);
                add_stg1_3 <= mult_stage(6) + mult_stage(7);
                add_stg1_4 <= mult_stage(8);

                -- STAGE 3: Adder Tree Level 2
                add_stg2_0 <= add_stg1_0 + add_stg1_1;
                add_stg2_1 <= add_stg1_2 + add_stg1_3;
                add_stg2_2 <= add_stg1_4;

                -- STAGE 4: Adder Tree Level 3
                add_stg3_0 <= add_stg2_0 + add_stg2_1;
                add_stg3_1 <= add_stg2_2;

                -- STAGE 5: Spatial Accumulation (Multiplexed for 1x1 or 3x3)
					 -- Assumes index (4) represents the center pixel of the 3x3 window array
					 if (mode_1x1_sr(4) = '1') then
						  -- 1x1 Mode: Bypass the adder tree entirely. 
						  -- Only the center multiplier contains valid data.
						  spatial_sum <= mult_stage(4);
					 else
						  -- 3x3 Mode: Utilize the full spatial adder tree
						  spatial_sum <= add_stg3_0 + add_stg3_1;
					 end if;
                
                -- STAGE 6: Channel Depth Accumulation
                if (valid_sr(4) = '1') then
                    if (first_sr(4) = '1') then
                        chan_accum <= spatial_sum; -- Initialize accumulator for new pixel
                    else
                        chan_accum <= chan_accum + spatial_sum; -- Accumulate depth
                    end if;
                end if;
                
                -- STAGE 7: Bias Addition and Leaky ReLU Activation
                if (valid_sr(5) = '1' and last_sr(5) = '1') then
                    v_biased_sum := chan_accum + signed(bias_in);
                    
                    if (v_biased_sum(31) = '0') then
                        -- Positive value: Linear pass-through
                        final_activation <= v_biased_sum;
                    else
                        -- Negative value: Leaky ReLU approximation (Alpha = 0.125)
                        -- Executes an arithmetic right shift by 3 to divide by 8
                        final_activation <= shift_right(v_biased_sum, 3);
                    end if;
                end if;
                
            end if;
        end if;
    end process conv_process;

    -- Asynchronous Output Ties
    conv_out  <= std_logic_vector(final_activation);
    
    -- Assert valid only when the final layer processing (Stage 7) completes
    out_valid <= valid_sr(6) and last_sr(6); 

end rtl;