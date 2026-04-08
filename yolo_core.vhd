LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- Import the custom CNN library
USE work.cnn_pkg.ALL;

entity yolo_core is
	Port ( 
		clk					:	in		std_logic;
		reset_n				:	in		std_logic;
		
		-- Memory Interface (Avalon-MM Master)
		mem_address			:	out	std_logic_vector(9 downto 0);
		mem_read				:	out	std_logic;
		mem_readdata		:	in		std_logic_vector(31 downto 0);
		
		-- Output Stream
		yolo_out				:	out	std_logic_vector(31 downto 0);
		yolo_valid			:	out	std_logic
	);
end yolo_core;

architecture arch of yolo_core is

	-- State Machine Definition
	type state_type is (S_IDLE, S_FETCH, S_LATCH, S_FIRE, S_WAIT_MAC);
	signal state : state_type := S_IDLE;

	-- Data Caching Registers
	signal pixel_reg_array	: window_3x3 := (others => (others => '0'));
	signal weight_reg_array	: window_3x3 := (others => (others => '0'));
	
	-- Internal Counters and Control
	signal read_count			: integer range 0 to 8 := 0;
	signal start_addr			: unsigned(9 downto 0) := (others => '0');
	
	-- CNN Cell Signals
	signal mac_data_valid	: std_logic := '0';
	signal mac_out_valid		: std_logic := '0';
	signal mac_result			: std_logic_vector(31 downto 0) := (others => '0');

begin

	-- Instantiate the 5-Stage Pipelined 3x3 Convolution Cell
	cnn_inst : component cnn_cell
		port map (
			clk				=> clk,
			reset_n			=> reset_n,
			enable			=> '1', -- Always running for now
			data_valid		=> mac_data_valid,
			out_valid		=> mac_out_valid,
			pixel_window	=> pixel_reg_array,
			weight_window	=> weight_reg_array,
			conv_out			=> mac_result
		);

	-- Main Control State Machine
	fsm_process : process(clk, reset_n)
	begin
		if (reset_n = '0') then
			state          <= S_IDLE;
			mem_address    <= (others => '0');
			mem_read       <= '0';
			read_count     <= 0;
			mac_data_valid <= '0';
			yolo_out       <= (others => '0');
			yolo_valid     <= '0';
			start_addr     <= (others => '0');
			
		elsif (rising_edge(clk)) then
			-- Default signal states (prevents accidental latches)
			mem_read       <= '0';
			mac_data_valid <= '0';
			yolo_valid     <= '0';

			case state is
				
				when S_IDLE =>
					-- Start the read sequence
					read_count <= 0;
					state      <= S_FETCH;
					
				when S_FETCH =>
					-- Request data from On-Chip Memory
					mem_address <= std_logic_vector(start_addr + read_count);
					mem_read    <= '1';
					state       <= S_LATCH;
					
				when S_LATCH =>
					-- Memory takes 1 cycle to respond. Grab the data now.
					pixel_reg_array(read_count)  <= mem_readdata(15 downto 0);
					weight_reg_array(read_count) <= mem_readdata(31 downto 16);
					
					-- Check if we have all 9 values
					if (read_count = 8) then
						state <= S_FIRE;
					else
						read_count <= read_count + 1;
						state      <= S_FETCH;
					end if;
					
				when S_FIRE =>
					-- Blast the valid flag to the CNN cell to start the 5-stage pipeline
					mac_data_valid <= '1';
					state          <= S_WAIT_MAC;
					
				when S_WAIT_MAC =>
					-- Wait for the pipelined result to pop out 5 cycles later
					if (mac_out_valid = '1') then
						yolo_out   <= mac_result;
						yolo_valid <= '1';
						-- Move to the next 9 addresses (just looping for testing)
						start_addr <= start_addr + 9; 
						state      <= S_IDLE;
					end if;
					
				when others =>
					state <= S_IDLE;
					
			end case;
		end if;
	end process fsm_process;

end arch;