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
			enable				:	in		std_logic; 
			data_valid			:	in		std_logic; 
			first_channel		:	in		std_logic; -- High when sending channel 0
			last_channel		:	in		std_logic; -- High when sending the final channel
			
			out_valid			:	out	std_logic; 
			
			-- Data Payload (One channel slice at a time)
			pixel_window		:	in		window_3x3;
			weight_window		:	in		window_3x3;
			
			-- Dot Product Output
			conv_out				:	out	std_logic_vector(31 downto 0)
		);
	end component cnn_cell;
end package cnn_pkg;

-- ====================================================================
-- CNN Cell Entity Definition (3x3 MAC with Depth Accumulator)
-- ====================================================================
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cnn_pkg.ALL;

entity cnn_cell is
	Port ( 
		clk					:	in		std_logic;
		reset_n				:	in		std_logic;
		
		enable				:	in		std_logic;
		data_valid			:	in		std_logic;
		first_channel		:	in		std_logic;
		last_channel		:	in		std_logic;
		
		out_valid			:	out	std_logic;
		pixel_window		:	in		window_3x3;
		weight_window		:	in		window_3x3;
		conv_out				:	out	std_logic_vector(31 downto 0)
	);
end cnn_cell;

architecture rtl of cnn_cell is

	-- Multiplier Pipeline (Stage 1)
	type mult_array is array (0 to 8) of signed(31 downto 0);
	signal mult_stage : mult_array := (others => (others => '0'));

	-- Adder Tree Pipeline (Stages 2-5)
	signal add_stg1_0, add_stg1_1, add_stg1_2, add_stg1_3, add_stg1_4 : signed(31 downto 0) := (others => '0');
	signal add_stg2_0, add_stg2_1, add_stg2_2                         : signed(31 downto 0) := (others => '0');
	signal add_stg3_0, add_stg3_1                                     : signed(31 downto 0) := (others => '0');
	signal spatial_sum                                                : signed(31 downto 0) := (others => '0');
	
	-- Channel Accumulator (Stage 6)
	signal chan_accum                                                 : signed(31 downto 0) := (others => '0');
	
	-- Shift Registers for tracking control signals through the 6 stages
	signal valid_sr : std_logic_vector(5 downto 0) := (others => '0');
	signal first_sr : std_logic_vector(5 downto 0) := (others => '0');
	signal last_sr  : std_logic_vector(5 downto 0) := (others => '0');

begin

	conv_process : process(clk, reset_n)
	begin
		if (reset_n = '0') then
			mult_stage  <= (others => (others => '0'));
			valid_sr    <= (others => '0');
			first_sr    <= (others => '0');
			last_sr     <= (others => '0');
			spatial_sum <= (others => '0');
			chan_accum  <= (others => '0');
			
		elsif (rising_edge(clk)) then
			
			if (enable = '1') then
			
				-- Shift control signals through the pipeline
				valid_sr <= valid_sr(4 downto 0) & data_valid;
				first_sr <= first_sr(4 downto 0) & first_channel;
				last_sr  <= last_sr(4 downto 0)  & last_channel;
			
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

				-- STAGE 5: Spatial Accumulation (The sum of the 3x3 slice)
				spatial_sum <= add_stg3_0 + add_stg3_1;
				
				-- STAGE 6: Channel Depth Accumulation
				if (valid_sr(4) = '1') then
					if (first_sr(4) = '1') then
						-- This is channel 0. Overwrite the accumulator to start fresh.
						chan_accum <= spatial_sum;
					else
						-- This is channel > 0. Add to the running total.
						chan_accum <= chan_accum + spatial_sum;
					end if;
				end if;
				
			end if;
		end if;
	end process conv_process;

	-- Asynchronous Output Ties
	conv_out  <= std_logic_vector(chan_accum);
	
	-- Only assert out_valid when the data is valid AND it was the last channel in the depth stack
	out_valid <= valid_sr(5) and last_sr(5); 

end rtl;