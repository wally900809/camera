FPGA configuration SPI x4
 - ISE/ Generate Programming File - ConfigurationRate: 33
 - ISE/ Generate Programming File - Set SPI Configuration Bus Width: 4


      OSERDESE2       -->          ISEDESE2
     ----------  H G F E D C B A  ----------
 A -|D1       Q|-----------------|D       Q1| - H
 B -|D2        |                 |        Q2| - G
 C -|D3        |                 |        Q3| - F
 D -|D4        |                 |        Q4| - E
 E -|D5        |                 |        Q5| - D
 F -|D6        |                 |        Q6| - C
 G -|D7        |                 |        Q7| - B
 H -|D8        |                 |        Q8| - A
     ----------                   ----------


                          ������ (X2)
 -- ������ -------------------5
|            |   ___
|             --|___|---------4 (3.3V)
|
|-----------------------------6 (0V)
|                ___
|---------------|___|---LED---7
|                ___
|---------------|___|---LED---8
