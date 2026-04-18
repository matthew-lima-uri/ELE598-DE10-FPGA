LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

-- Import the custom CNN library
USE work.cnn_pkg.ALL;

entity yolo_core is
    Port ( 
        clk                 : in  std_logic;
        reset_n             : in  std_logic;
        
        -- Memory Interface (Avalon-MM Master)
        mem_address         : out std_logic_vector(15 downto 0);
        mem_read            : out std_logic;
        mem_readdata        : in  std_logic_vector(31 downto 0);
        
        -- Output Stream
        yolo_out            : out std_logic_vector(31 downto 0);
        yolo_valid          : out std_logic
    );
end yolo_core;

architecture arch of yolo_core is

    -- Constants
    constant CHANNELS       : integer := 3; -- Input depth

    -- State Machine Definition
    type state_type is (S_IDLE, S_FETCH_BIAS, S_LATCH_BIAS, S_FETCH, S_LATCH, S_FIRE, S_WAIT_MAC);
    signal state : state_type := S_IDLE;

    -- Data Caching Registers
    signal pixel_reg_array  : window_3x3 := (others => (others => '0'));
    signal weight_reg_array : window_3x3 := (others => (others => '0'));
    signal bias_reg         : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Internal Counters and Address Pointers
    signal read_count       : integer range 0 to 8 := 0;
    signal channel_count    : integer range 0 to CHANNELS := 0;
    signal base_addr        : unsigned(15 downto 0) := (others => '0');
    signal data_ptr         : unsigned(15 downto 0) := (others => '0');
    
    -- CNN Cell Signals
    signal mac_data_valid   : std_logic := '0';
    signal mac_first        : std_logic := '0';
    signal mac_last         : std_logic := '0';
    signal mac_out_valid    : std_logic := '0';
    signal mac_result       : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- Instantiate the 7-Stage CNN Cell (Accumulator + Bias + Activation)
    cnn_inst : component cnn_cell
        port map (
            clk             => clk,
            reset_n         => reset_n,
            enable          => '1', 
            
            -- Handshaking and Channel Control
            data_valid      => mac_data_valid,
            first_channel   => mac_first,
            last_channel    => mac_last,
            out_valid       => mac_out_valid,
            
            -- Data Payload
            pixel_window    => pixel_reg_array,
            weight_window   => weight_reg_array,
            bias_in         => bias_reg,
            
            conv_out        => mac_result
        );

    -- Main Control State Machine
    fsm_process : process(clk, reset_n)
    begin
        if (reset_n = '0') then
            state          <= S_IDLE;
            mem_address    <= (others => '0');
            mem_read       <= '0';
            read_count     <= 0;
            channel_count  <= 0;
            mac_data_valid <= '0';
            mac_first      <= '0';
            mac_last       <= '0';
            yolo_out       <= (others => '0');
            yolo_valid     <= '0';
            base_addr      <= (others => '0');
            data_ptr       <= (others => '0');
            bias_reg       <= (others => '0');
            
        elsif (rising_edge(clk)) then
            -- Default signal states
            mem_read       <= '0';
            mac_data_valid <= '0';
            mac_first      <= '0';
            mac_last       <= '0';
            yolo_valid     <= '0';

            case state is
                
                when S_IDLE =>
                    read_count    <= 0;
                    channel_count <= 0;
                    state         <= S_FETCH_BIAS;
                    
                when S_FETCH_BIAS =>
                    -- Address 0 of the current block holds the folded bias parameter
                    mem_address <= std_logic_vector(base_addr);
                    mem_read    <= '1';
                    state       <= S_LATCH_BIAS;
                    
                when S_LATCH_BIAS =>
                    bias_reg <= mem_readdata;
                    -- Offset the data pointer to skip the bias word
                    data_ptr <= base_addr + 1; 
                    state    <= S_FETCH;
                    
                when S_FETCH =>
                    -- Fetch spatial data
                    mem_address <= std_logic_vector(data_ptr + read_count);
                    mem_read    <= '1';
                    state       <= S_LATCH;
                    
                when S_LATCH =>
                    pixel_reg_array(read_count)  <= mem_readdata(15 downto 0);
                    weight_reg_array(read_count) <= mem_readdata(31 downto 16);
                    
                    if (read_count = 8) then
                        state <= S_FIRE;
                    else
                        read_count <= read_count + 1;
                        state      <= S_FETCH;
                    end if;
                    
                when S_FIRE =>
                    mac_data_valid <= '1';
                    
                    if (channel_count = 0) then
                        mac_first <= '1';
                    end if;
                    
                    if (channel_count = CHANNELS - 1) then
                        mac_last <= '1';
                        state    <= S_WAIT_MAC;
                    else
                        channel_count <= channel_count + 1;
                        read_count    <= 0;
                        -- Shift the pointer 9 words forward for the next depth slice
                        data_ptr      <= data_ptr + 9; 
                        state         <= S_FETCH;
                    end if;
                    
                when S_WAIT_MAC =>
                    -- Wait for Stage 7 to complete
                    if (mac_out_valid = '1') then
                        yolo_out   <= mac_result;
                        yolo_valid <= '1';
                        
                        -- Calculate the memory stride for the next iteration:
                        -- 1 Bias word + (9 Spatial words * CHANNELS)
                        base_addr  <= base_addr + 1 + (9 * CHANNELS);
                        state      <= S_IDLE;
                    end if;
                    
                when others =>
                    state <= S_IDLE;
                    
            end case;
        end if;
    end process fsm_process;

end arch;