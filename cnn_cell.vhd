LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- ====================================================================
-- CNN Component Library Package
-- Import this using: USE work.cnn_pkg.ALL;
-- ====================================================================
package cnn_pkg is
	-- Component Declaration
	component cnn_cell is
		Port ( 
			clk					:	in		std_logic;
			reset_n				:	in		std_logic;
			-- Data and Weights
			data_in				:	in		std_logic_vector(15 downto 0);
			weight_in			:	in		std_logic_vector(15 downto 0);
			-- Output
			mac_out				:	out	std_logic_vector(31 downto 0)
		);
	end component cnn_cell;
end package cnn_pkg;

-- ====================================================================
-- CNN Cell Entity Definition
-- ====================================================================
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity cnn_cell is
	Port ( 
		clk					:	in		std_logic;
		reset_n				:	in		std_logic;
		-- Data and Weights
		data_in				:	in		std_logic_vector(15 downto 0);
		weight_in			:	in		std_logic_vector(15 downto 0);
		-- Output
		mac_out				:	out	std_logic_vector(31 downto 0)
	);
end cnn_cell;

architecture rtl of cnn_cell is

	signal	reg_data				:	signed(15 downto 0)			:= (others => '0');
	signal	reg_weight			:	signed(15 downto 0)			:= (others => '0');
	signal	reg_mult				:	signed(31 downto 0)			:= (others => '0');
	signal	reg_accum			:	signed(31 downto 0)			:= (others => '0');

begin

	-- Synchronous MAC Process
	mac_process	:	process(clk, reset_n)
	begin
		if (reset_n = '0') then
			reg_data				<= (others => '0');
			reg_weight			<= (others => '0');
			reg_mult				<= (others => '0');
			reg_accum			<= (others => '0');
		elsif (rising_edge(clk)) then
			-- Register the inputs to prevent routing delays
			reg_data				<= signed(data_in);
			reg_weight			<= signed(weight_in);
			
			-- Multiply and Accumulate
			reg_mult				<= reg_data * reg_weight;
			reg_accum			<= reg_accum + reg_mult;
		end if;
	end process mac_process;

	-- Asynchronous Ties
	mac_out <= std_logic_vector(reg_accum);

end rtl;