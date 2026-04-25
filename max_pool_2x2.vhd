LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- ====================================================================
-- Entity: max_pool_2x2
-- Description: 2-Stage pipelined 2x2 Max Pooling unit.
-- Evaluates a 2x2 window of activated 32-bit pixels and outputs 
-- the maximum value to compress the spatial dimensions of the feature map.
-- ====================================================================
entity max_pool_2x2 is
    Port ( 
        clk             : in  std_logic;
        reset_n         : in  std_logic;
        
        -- Control Logic
        enable          : in  std_logic;
        data_valid      : in  std_logic;
        
        -- 2x2 Spatial Window (Activated Inputs)
        pixel_00        : in  std_logic_vector(31 downto 0); -- Top-Left
        pixel_01        : in  std_logic_vector(31 downto 0); -- Top-Right
        pixel_10        : in  std_logic_vector(31 downto 0); -- Bottom-Left
        pixel_11        : in  std_logic_vector(31 downto 0); -- Bottom-Right
        
        -- Output
        out_valid       : out std_logic;
        max_out         : out std_logic_vector(31 downto 0)
    );
end max_pool_2x2;

architecture rtl of max_pool_2x2 is

    -- Stage 1 Pipeline Registers
    signal max_top      : signed(31 downto 0) := (others => '0');
    signal max_bot      : signed(31 downto 0) := (others => '0');
    
    -- Stage 2 Pipeline Register
    signal max_final    : signed(31 downto 0) := (others => '0');
    
    -- Shift register for valid data handshaking (2 stages)
    signal valid_sr     : std_logic_vector(1 downto 0) := "00";

begin

    pool_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            max_top     <= (others => '0');
            max_bot     <= (others => '0');
            max_final   <= (others => '0');
            valid_sr    <= (others => '0');
            
        elsif (rising_edge(clk)) then
            if (enable = '1') then
                
                -- Shift the valid flag through the 2-stage pipeline
                valid_sr <= valid_sr(0) & data_valid;
                
                -- STAGE 1: Parallel Row Comparisons
                if (signed(pixel_00) > signed(pixel_01)) then
                    max_top <= signed(pixel_00);
                else
                    max_top <= signed(pixel_01);
                end if;
                
                if (signed(pixel_10) > signed(pixel_11)) then
                    max_bot <= signed(pixel_10);
                else
                    max_bot <= signed(pixel_11);
                end if;
                
                -- STAGE 2: Final Column Comparison
                if (max_top > max_bot) then
                    max_final <= max_top;
                else
                    max_final <= max_bot;
                end if;
                
            end if;
        end if;
    end process pool_process;

    -- Asynchronous Output Ties
    max_out   <= std_logic_vector(max_final);
    out_valid <= valid_sr(1); -- Asserts high when Stage 2 completes

end rtl;