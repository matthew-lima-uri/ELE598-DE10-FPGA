LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cnn_pkg.ALL;

-- ====================================================================
-- Entity: line_buffer
-- Description: Dual-row FIFO buffer for 2D spatial convolution. 
-- Caches incoming pixel streams to provide a parallel 3x3 output 
-- window without redundant external memory reads.
-- ====================================================================
entity line_buffer is
    Generic (
        -- Maximum width of the image/feature map (e.g., 416 for YOLOv3-tiny)
        IMAGE_WIDTH     : integer := 416
    );
    Port ( 
        clk             : in  std_logic;
        reset_n         : in  std_logic;
        
        -- Control
        shift_en        : in  std_logic; -- High when new pixel arrives
        
        -- Data Stream In (Single Pixel)
        pixel_in        : in  std_logic_vector(15 downto 0);
        
        -- 3x3 Parallel Output Window
        window_out      : out window_3x3
    );
end line_buffer;

architecture rtl of line_buffer is

    -- Inferable Block RAM types for the two row buffers
    type row_ram_type is array (0 to IMAGE_WIDTH - 1) of std_logic_vector(15 downto 0);
    
    -- RAM blocks
    signal row_fifo_1   : row_ram_type := (others => (others => '0'));
    signal row_fifo_2   : row_ram_type := (others => (others => '0'));
    
    -- Write/Read Pointers
    signal ptr          : integer range 0 to IMAGE_WIDTH - 1 := 0;
    
    -- Shift registers for the 3x3 window extraction
    signal r0_c0, r0_c1, r0_c2 : std_logic_vector(15 downto 0) := (others => '0'); -- Top row
    signal r1_c0, r1_c1, r1_c2 : std_logic_vector(15 downto 0) := (others => '0'); -- Middle row
    signal r2_c0, r2_c1, r2_c2 : std_logic_vector(15 downto 0) := (others => '0'); -- Bottom row (Current incoming)

begin

    buffer_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            ptr   <= 0;
            r0_c0 <= (others => '0'); r0_c1 <= (others => '0'); r0_c2 <= (others => '0');
            r1_c0 <= (others => '0'); r1_c1 <= (others => '0'); r1_c2 <= (others => '0');
            r2_c0 <= (others => '0'); r2_c1 <= (others => '0'); r2_c2 <= (others => '0');
            
        elsif (rising_edge(clk)) then
            if (shift_en = '1') then
            
                -- 1. Read from the FIFOs to get the historical vertical pixels
                -- r1_c2 gets the pixel from 1 row ago, r0_c2 gets the pixel from 2 rows ago
                r1_c2 <= row_fifo_1(ptr);
                r0_c2 <= row_fifo_2(ptr);
                
                -- 2. Write the current incoming pixel and the cascading row pixel to the FIFOs
                row_fifo_1(ptr) <= pixel_in;
                row_fifo_2(ptr) <= row_fifo_1(ptr);
                
                -- 3. Shift the horizontal window (Columns)
                -- Bottom Row (Incoming Stream)
                r2_c0 <= r2_c1;
                r2_c1 <= r2_c2;
                r2_c2 <= pixel_in;
                
                -- Middle Row (1 Row Delayed)
                r1_c0 <= r1_c1;
                r1_c1 <= r1_c2;
                
                -- Top Row (2 Rows Delayed)
                r0_c0 <= r0_c1;
                r0_c1 <= r0_c2;
                
                -- 4. Manage the circular pointer
                if (ptr = IMAGE_WIDTH - 1) then
                    ptr <= 0;
                else
                    ptr <= ptr + 1;
                end if;
                
            end if;
        end if;
    end process buffer_process;

    -- Map the internal shift registers directly to the output window array
    -- This matches the expected format of the cnn_cell
    window_out(0) <= r0_c0; window_out(1) <= r0_c1; window_out(2) <= r0_c2;
    window_out(3) <= r1_c0; window_out(4) <= r1_c1; window_out(5) <= r1_c2;
    window_out(6) <= r2_c0; window_out(7) <= r2_c1; window_out(8) <= r2_c2;

end rtl;