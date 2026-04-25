LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.cnn_pkg.ALL;

-- ====================================================================
-- Entity: yolo_core
-- Description: Top-level Avalon-MM Master controller for the CNN 
-- datapath. Manages memory streaming, line buffering, convolution, 
-- activation, and max pooling, followed by memory write-back.
-- ====================================================================
entity yolo_core is
    Port ( 
        clk                 : in  std_logic;
        reset_n             : in  std_logic;
        
        -- Memory Interface (Avalon-MM Read/Write Master)
        mem_address         : out std_logic_vector(15 downto 0);
        mem_read            : out std_logic;
        mem_readdata        : in  std_logic_vector(31 downto 0);
        mem_write           : out std_logic;
        mem_writedata       : out std_logic_vector(31 downto 0);
        
        -- Output Stream (For Top-Level Debugging/Verification)
        yolo_out            : out std_logic_vector(31 downto 0);
        yolo_valid          : out std_logic
    );
end yolo_core;

architecture arch of yolo_core is

    -- System Configuration
    constant CHANNELS       : integer := 3;
    constant IMG_WIDTH      : integer := 416;
    
    -- Memory Offsets (Preventing read/write collisions in shared memory)
    constant BASE_READ_ADDR  : unsigned(15 downto 0) := x"0000";
    constant BASE_WRITE_ADDR : unsigned(15 downto 0) := x"1000"; 

    -- FSM Definition 
    type state_type is (S_IDLE, S_FETCH_BIAS, S_STREAM_READ, S_LATCH_AND_SHIFT, S_WAIT_PIPELINE, S_WRITE_BACK);
    signal state : state_type := S_IDLE;

    -- Datapath Interconnect Signals
    signal stream_enable    : std_logic := '0';
    signal current_pixel    : std_logic_vector(15 downto 0) := (others => '0');
    signal spatial_window   : window_3x3;
    
    signal cnn_bias         : std_logic_vector(31 downto 0) := (others => '0');
    signal cnn_first_chan   : std_logic := '0';
    signal cnn_last_chan    : std_logic := '0';
    
    signal cnn_out_valid    : std_logic := '0';
    signal cnn_act_pixel    : std_logic_vector(31 downto 0) := (others => '0');
	 
	 -- Output Pooling Caching (The Output Row Buffer)
    type act_row_type is array (0 to IMG_WIDTH - 1) of std_logic_vector(31 downto 0);
    signal act_row_fifo     : act_row_type := (others => (others => '0'));
    
    -- Stride-2 Coordinate Trackers
    signal col_cnt          : integer range 0 to IMG_WIDTH - 1 := 0;
    signal row_cnt          : integer range 0 to IMG_WIDTH - 1 := 0;
    
    -- 2x2 Assembly Registers
    signal pool_00, pool_01, pool_10, pool_11 : std_logic_vector(31 downto 0) := (others => '0');
    signal pool_trigger     : std_logic := '0';
    signal pool_out_valid   : std_logic := '0';
    signal pool_max_result  : std_logic_vector(31 downto 0) := (others => '0');

    -- Output Pooling Caching 
    signal pool_00, pool_01, pool_10, pool_11 : std_logic_vector(31 downto 0) := (others => '0');
    signal pool_out_valid   : std_logic := '0';
    signal pool_max_result  : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Memory Pointers
    signal read_ptr         : unsigned(15 downto 0) := BASE_READ_ADDR;
    signal write_ptr        : unsigned(15 downto 0) := BASE_WRITE_ADDR;

begin

    -- 1. Input Line Buffer (Caches raw memory streams to build 3x3 windows)
    input_buffer_inst : component line_buffer
        generic map ( IMAGE_WIDTH => IMG_WIDTH )
        port map (
            clk         => clk,
            reset_n     => reset_n,
            shift_en    => stream_enable,
            pixel_in    => current_pixel,
            window_out  => spatial_window
        );

    -- 2. CNN MAC Pipeline (7-Stage Convolution, Accumulation, and Activation)
    cnn_pipeline_inst : component cnn_cell
        port map (
            clk             => clk,
            reset_n         => reset_n,
            enable          => '1', 
            data_valid      => stream_enable,
            first_channel   => cnn_first_chan,
            last_channel    => cnn_last_chan,
            out_valid       => cnn_out_valid,
            pixel_window    => spatial_window,
            weight_window   => spatial_window,
            bias_in         => cnn_bias,
            conv_out        => cnn_act_pixel
        );

    -- 3. Max Pooling Layer (2x2 Compression)
    max_pool_inst : component max_pool_2x2
        port map (
            clk         => clk,
            reset_n     => reset_n,
            enable      => '1',
            data_valid  => pool_trigger,  -- Triggered explicitly by the Stride-2 logic
            pixel_00    => pool_00,
            pixel_01    => pool_01,
            pixel_10    => pool_10,
            pixel_11    => pool_11,
            out_valid   => pool_out_valid,
            max_out     => pool_max_result
        );
		  
	 -- ====================================================================
    -- Output Row Cache & Stride-2 Assembly Logic
    -- ====================================================================
    output_cache_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            col_cnt      <= 0;
            row_cnt      <= 0;
            pool_trigger <= '0';
            pool_00 <= (others => '0'); pool_01 <= (others => '0');
            pool_10 <= (others => '0'); pool_11 <= (others => '0');
            -- Note: act_row_fifo is not explicitly reset to save routing resources
            
        elsif (rising_edge(clk)) then
            -- Default state
            pool_trigger <= '0';
            
            -- When the 7-Stage CNN Pipeline yields a completed, activated pixel
            if (cnn_out_valid = '1') then
                
                -- 1. Shift the horizontal registers
                pool_10 <= pool_11;               -- Shift bottom row
                pool_11 <= cnn_act_pixel;         -- Insert current pixel
                
                pool_00 <= pool_01;               -- Shift top row
                pool_01 <= act_row_fifo(col_cnt); -- Fetch pixel from 1 row ago
                
                -- 2. Update the Output Row FIFO with the current pixel for the next row's use
                act_row_fifo(col_cnt) <= cnn_act_pixel;
                
                -- 3. Stride-2 Evaluation
                -- Only trigger the Max Pool module if on an ODD row and ODD column
                -- (meaning a full 2x2 block has just completed shifting into the registers)
                if ((col_cnt mod 2 = 1) and (row_cnt mod 2 = 1)) then
                    pool_trigger <= '1';
                end if;
                
                -- 4. Manage Spatial Coordinates
                if (col_cnt = IMG_WIDTH - 1) then
                    col_cnt <= 0;
                    if (row_cnt = IMG_WIDTH - 1) then
                        row_cnt <= 0;
                    else
                        row_cnt <= row_cnt + 1;
                    end if;
                else
                    col_cnt <= col_cnt + 1;
                end if;
                
            end if;
        end if;
    end process output_cache_process;

    -- Main Control State Machine (Read/Write Avalon-MM Master)
    fsm_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            state           <= S_IDLE;
            mem_address     <= (others => '0');
            mem_read        <= '0';
            mem_write       <= '0';
            mem_writedata   <= (others => '0');
            stream_enable   <= '0';
            read_ptr        <= BASE_READ_ADDR;
            write_ptr       <= BASE_WRITE_ADDR;
            cnn_first_chan  <= '0';
            cnn_last_chan   <= '0';
            yolo_out        <= (others => '0');
            yolo_valid      <= '0';
            
        elsif (rising_edge(clk)) then
            -- Default signal states
            mem_read      <= '0';
            mem_write     <= '0';
            stream_enable <= '0';
            yolo_valid    <= '0';

            case state is
                
                when S_IDLE =>
                    state <= S_FETCH_BIAS;
                    
                when S_FETCH_BIAS =>
                    mem_address <= std_logic_vector(read_ptr);
                    mem_read    <= '1';
                    state       <= S_STREAM_READ;
                    read_ptr    <= read_ptr + 1;
                    
                when S_STREAM_READ =>
                    mem_address <= std_logic_vector(read_ptr);
                    mem_read    <= '1';
                    state       <= S_LATCH_AND_SHIFT;
                    
                when S_LATCH_AND_SHIFT =>
                    current_pixel  <= mem_readdata(15 downto 0);
                    stream_enable  <= '1'; 
                    read_ptr       <= read_ptr + 1;
                    state          <= S_WAIT_PIPELINE;
                    
                when S_WAIT_PIPELINE =>
                    if (pool_out_valid = '1') then
                        -- Route the data to the debug ports
                        yolo_out   <= pool_max_result;
                        yolo_valid <= '1';
                        
                        -- Transition to write the pooled result back to memory
                        state      <= S_WRITE_BACK;
                    else
                        -- Continue streaming if pipeline has not produced a final pooled pixel
                        state      <= S_STREAM_READ;
                    end if;
                    
                when S_WRITE_BACK =>
                    -- Execute the Avalon-MM Write transaction
                    mem_address   <= std_logic_vector(write_ptr);
                    mem_writedata <= pool_max_result;
                    mem_write     <= '1';
                    
                    -- Increment the write pointer and return to reading the next block
                    write_ptr     <= write_ptr + 1;
                    state         <= S_STREAM_READ;
                    
                when others =>
                    state <= S_IDLE;
                    
            end case;
            
        end if;
    end process fsm_process;

end arch;