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

    type row_ram_type is array (0 to IMAGE_WIDTH - 1) of std_logic_vector(15 downto 0);
    signal row_fifo_1   : row_ram_type := (others => (others => '0'));
    signal row_fifo_2   : row_ram_type := (others => (others => '0'));
    
    signal ptr          : integer range 0 to IMAGE_WIDTH - 1 := 0;
    
    -- Internal column tracker for Zero-Padding
    signal col_cnt      : integer range 0 to IMAGE_WIDTH - 1 := 0;

    signal r0_c0, r0_c1, r0_c2 : std_logic_vector(15 downto 0) := (others => '0');
    signal r1_c0, r1_c1, r1_c2 : std_logic_vector(15 downto 0) := (others => '0');
    signal r2_c0, r2_c1, r2_c2 : std_logic_vector(15 downto 0) := (others => '0');

begin

    buffer_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            ptr     <= 0;
            col_cnt <= 0;
            r0_c0 <= (others => '0'); r0_c1 <= (others => '0'); r0_c2 <= (others => '0');
            r1_c0 <= (others => '0'); r1_c1 <= (others => '0'); r1_c2 <= (others => '0');
            r2_c0 <= (others => '0'); r2_c1 <= (others => '0'); r2_c2 <= (others => '0');
            
        elsif (rising_edge(clk)) then
            if (shift_en = '1') then
                r1_c2 <= row_fifo_1(ptr);
                r0_c2 <= row_fifo_2(ptr);
                
                row_fifo_1(ptr) <= pixel_in;
                row_fifo_2(ptr) <= row_fifo_1(ptr);
                
                r2_c0 <= r2_c1; r2_c1 <= r2_c2; r2_c2 <= pixel_in;
                r1_c0 <= r1_c1; r1_c1 <= r1_c2;
                r0_c0 <= r0_c1; r0_c1 <= r0_c2;
                
                if (ptr = IMAGE_WIDTH - 1) then
                    ptr <= 0;
                else
                    ptr <= ptr + 1;
                end if;

                -- Track the incoming stream column to calculate edge padding
                if (col_cnt = IMAGE_WIDTH - 1) then
                    col_cnt <= 0;
                else
                    col_cnt <= col_cnt + 1;
                end if;
                
            end if;
        end if;
    end process buffer_process;

    -- Multiplex the output window to enforce "Same" padding
    
    -- Left Edge Padding (Forces Left Column to 0)
    window_out(0) <= (others => '0') when (col_cnt = 1) else r0_c0;
    window_out(3) <= (others => '0') when (col_cnt = 1) else r1_c0;
    window_out(6) <= (others => '0') when (col_cnt = 1) else r2_c0;

    -- Center Column (Always valid)
    window_out(1) <= r0_c1;
    window_out(4) <= r1_c1;
    window_out(7) <= r2_c1;

    -- Right Edge Padding (Forces Right Column to 0)
    window_out(2) <= (others => '0') when (col_cnt = 0) else r0_c2;
    window_out(5) <= (others => '0') when (col_cnt = 0) else r1_c2;
    window_out(8) <= (others => '0') when (col_cnt = 0) else r2_c2;

end rtl;