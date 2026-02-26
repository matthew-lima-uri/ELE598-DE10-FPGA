LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

entity CNNAccelerator is
    Port ( 
        CLOCK_50 	: 	in 	std_logic;
		  CLOCK2_50	: 	in 	std_logic;
		  CLOCK3_50	: 	in 	std_logic;
		  CLOCK4_50	: 	in 	std_logic;
        KEY		 	:	in 	std_logic_vector(3 downto 0);
		  SW			:	in		std_logic_vector(9 downto 0);
        LEDR	 	: 	out 	std_logic_vector(9 downto 0)
    );
end CNNAccelerator;

architecture arch of CNNAccelerator is

constant step_val		:	integer						:= 500000;
signal	counter		:	unsigned(9 downto 0) 	:= (others => '0');
signal	step_down	:	unsigned(31 downto 0)	:= (others => '0');
signal	step_latch	:	std_logic					:= '0';

begin
    
	 LEDR			<=	std_logic_vector(counter);
	 
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