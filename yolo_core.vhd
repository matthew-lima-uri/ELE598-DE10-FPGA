LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- Import the custom CNN library
USE work.cnn_pkg.ALL;

entity yolo_core is
	Port ( 
		clk					:	in		std_logic;
		reset_n				:	in		std_logic;
		-- Input Stream
		pixel_data			:	in		std_logic_vector(15 downto 0);
		weight_data			:	in		std_logic_vector(15 downto 0);
		-- Output Stream
		yolo_out				:	out	std_logic_vector(31 downto 0)
	);
end yolo_core;

architecture arch of yolo_core is

	signal	cell_0_out			:	std_logic_vector(31 downto 0)			:= (others => '0');
	signal	cell_1_out			:	std_logic_vector(31 downto 0)			:= (others => '0');

begin

	-- Instantiate CNN Cell 0
	cell_0 : component cnn_cell
		port map (
			clk					=> clk,
			reset_n				=> reset_n,
			-- Feed the shared inputs
			data_in				=> pixel_data,
			weight_in			=> weight_data,
			mac_out				=> cell_0_out
		);

	-- Instantiate CNN Cell 1
	cell_1 : component cnn_cell
		port map (
			clk					=> clk,
			reset_n				=> reset_n,
			-- Feed the shared inputs
			data_in				=> pixel_data,
			weight_in			=> weight_data,
			mac_out				=> cell_1_out
		);

	-- Asynchronous Ties
	-- Hardwiring cell 0 to the output for now so the Quartus Fitter 
	-- doesn't optimize the whole block into oblivion during synthesis
	yolo_out <= cell_0_out;

end arch;