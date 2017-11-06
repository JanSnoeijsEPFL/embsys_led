library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_tb is
	end entity led_tb;
	
architecture bench of led_tb is
	
	constant CLK_PER: time := 20 ns;
	
	signal Clk_tb, nReset_tb, Read_tb, Write_tb, ChipSelect_tb, LedData_tb: std_logic:= '0';
	signal ReadData_tb, WriteData_tb: std_logic_vector(7 downto 0);
	signal Address_tb: std_logic_vector(5 downto 0);
	signal stop: boolean := false;

begin
	
	DUV: entity work.led
		port map ( 	Clk => Clk_tb, 
				 	nReset=>nReset_tb, 
			       	Address=> Address_tb, 
			       	ChipSelect=> ChipSelect_tb,
					Read=> Read_tb,
					Write=> Write_tb,
					ReadData => ReadData_tb,
					WriteData => WriteData_tb,
					LedData => LedData_tb
					 );
		
	Clk_tb <= not Clk_tb after CLK_PER/2 when not stop;
    nReset_tb <= '1', '0' after CLK_PER/4, '1' after 3*CLK_PER/4;
    process
      		procedure do_ctrl (
      			start: in std_logic_vector (1 downto 0)
      				) is
      		begin
      			Address_tb <= "000011";
      			ChipSelect_tb <= '1';
      			Write_tb <= '1';
      			WriteData_tb <= "000000" & start;
      			wait until rising_edge(Clk_tb);
      		end procedure do_ctrl;
      		
      		procedure do_load (
      			rgb: in integer;
      			led_nb: in integer;
      			color_byte: in integer
      		) is
      		
      		begin
      			Address_tb <= std_logic_vector(to_unsigned(led_nb,4)) & std_logic_vector(to_unsigned(rgb, 2));
      			ChipSelect_tb <= '1';
      			Write_tb <= '1';
      			WriteData_tb <= std_logic_vector(to_unsigned(color_byte, WriteData_tb'length));
      			wait until rising_edge(Clk_tb);
      		end procedure;
      	
      begin
      	Address_tb <= (others => '0');
      	ChipSelect_tb <= '0';
      	Write_tb <= '0';
      	Read_tb <= '1';
      	WriteData_tb <= (others => '0');
      		
      	
      	wait until rising_edge(nReset_tb);
      	wait until falling_edge(Clk_tb);
      	do_ctrl("01");
      	for i in 0 to 15 loop
      		for j in 0 to 2 loop
      			do_load(j, i, 2);
      		end loop;
      	end loop;
      	wait until rising_edge(Clk_tb);
      	do_ctrl("10");
      	wait until rising_edge(Clk_tb);
      	Address_tb <= "000011";
      	ChipSelect_tb <= '1';
      	Write_tb <= '0';
      	Read_tb <= '1';
      	WriteData_tb <= (others => '0');
      	wait for 48384 ns ;
      	stop <= true;
      	wait;
      end process;
      	
  end architecture bench;