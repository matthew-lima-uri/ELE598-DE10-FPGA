LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- ====================================================================
-- CNN Component Library Package
-- ====================================================================
package cnn_pkg is
	-- Define a custom array type to pass a 3x3 window of 16-bit data
	type window_3x3 is array (0 to 8) of std_logic_vector(15 downto 0);

	-- Component Declaration
	component cnn_cell is
		Port ( 
			clk					:	in		std_logic;
			reset_n				:	in		std_logic;
			
			-- Control Logic
			enable				:	in		std_logic; -- Master freeze switch
			data_valid			:	in		std_logic; -- High when input data is good
			out_valid			:	out	std_logic; -- High when output data is good
			
			-- 3x3 Windows for Image Data and Weights
			pixel_window		:	in		window_3x3;
			weight_window		:	in		window_3x3;
			
			-- Dot Product Output
			conv_out				:	out	std_logic_vector(31 downto 0)
		);
	end component cnn_cell;
end package cnn_pkg;

-- ====================================================================
-- CNN Cell Entity Definition (3x3 Pipelined Convolution)
-- ====================================================================
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cnn_pkg.ALL;

entity cnn_cell is
	Port ( 
		clk					:	in		std_logic;
		reset_n				:	in		std_logic;
		
		-- Control Logic
		enable				:	in		std_logic;
		data_valid			:	in		std_logic;
		out_valid			:	out	std_logic;
		
		-- Data Payload
		pixel_window		:	in		window_3x3;
		weight_window		:	in		window_3x3;
		conv_out				:	out	std_logic_vector(31 downto 0)
	);
end cnn_cell;

architecture rtl of cnn_cell is

	-- Internal types for the multiplier pipeline
	type mult_array is array (0 to 8) of signed(31 downto 0);
	signal mult_stage : mult_array := (others => (others => '0'));

	-- Adder Tree Pipeline Registers
	signal add_stg1_0, add_stg1_1, add_stg1_2, add_stg1_3, add_stg1_4 : signed(31 downto 0) := (others => '0');
	signal add_stg2_0, add_stg2_1, add_stg2_2                         : signed(31 downto 0) := (others => '0');
	signal add_stg3_0, add_stg3_1                                     : signed(31 downto 0) := (others => '0');
	signal final_sum                                                  : signed(31 downto 0) := (others => '0');
	
	-- 5-Bit Shift Register to track data validity through the pipeline
	signal valid_sr                                                   : std_logic_vector(4 downto 0) := (others => '0');

begin

	-- 5-Stage Pipelined 3x3 Convolution Process
	conv_process : process(clk, reset_n)
	begin
		if (reset_n = '0') then
			mult_stage  <= (others => (others => '0'));
			valid_sr    <= (others => '0');
			final_sum   <= (others => '0');
			
		elsif (rising_edge(clk)) then
			
			-- Only process new data or shift the pipeline if ENABLED
			if (enable = '1') then
			
				-- Shift the valid flag through the 5 stages
				valid_sr <= valid_sr(3 downto 0) & data_valid;
			
				-- STAGE 1: Parallel Multiplication (9 Multipliers firing at once)
				for i in 0 to 8 loop
					mult_stage(i) <= signed(pixel_window(i)) * signed(weight_window(i));
				end loop;

				-- STAGE 2: Adder Tree Level 1 (Summing pairs)
				add_stg1_0 <= mult_stage(0) + mult_stage(1);
				add_stg1_1 <= mult_stage(2) + mult_stage(3);
				add_stg1_2 <= mult_stage(4) + mult_stage(5);
				add_stg1_3 <= mult_stage(6) + mult_stage(7);
				add_stg1_4 <= mult_stage(8); -- Odd man out

				-- STAGE 3: Adder Tree Level 2
				add_stg2_0 <= add_stg1_0 + add_stg1_1;
				add_stg2_1 <= add_stg1_2 + add_stg1_3;
				add_stg2_2 <= add_stg1_4;

				-- STAGE 4: Adder Tree Level 3
				add_stg3_0 <= add_stg2_0 + add_stg2_1;
				add_stg3_1 <= add_stg2_2;

				-- STAGE 5: Final Accumulation
				final_sum  <= add_stg3_0 + add_stg3_1;
				
			end if;
		end if;
	end process conv_process;

	-- Asynchronous Output Ties
	conv_out  <= std_logic_vector(final_sum);
	out_valid <= valid_sr(4); -- Asserts high exactly when STAGE 5 finishes

end rtl;