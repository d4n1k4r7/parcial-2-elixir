defmodule Ciudad do
  defstruct [:id, :nombre, :habitantes]
end

defmodule Movimiento do
  defstruct [:codigo, :id_ciudad, :hora_inicio, :hora_final, :magnitud, :profundidad]
end

defmodule Validador do
  def parse_hora(str) do
    case Time.from_iso8601(str) do
      {:ok, time} -> {:ok, time}
      _ -> :error
    end
  end

  def parse_float(str) do
    case Float.parse(str) do
      {num, ""} -> {:ok, num}
      _ -> :error
    end
  end

  def parse_int(str) do
    case Integer.parse(str) do
      {num, ""} -> {:ok, num}
      _ -> :error
    end
  end
end

defmodule Lector do
  def leer_ciudades(ruta, parent_pid) do
    case File.read(ruta) do
      {:ok, contenido} ->
        lineas = String.split(contenido, ["\r\n", "\n"], trim: false)
        {ciudades, rechazados} = procesar_lineas_ciudades(lineas, [], 0)
        send(parent_pid, {:ciudades, {:ok, ciudades, rechazados}})

      {:error, razon} ->
        send(parent_pid, {:ciudades, {:error, "Error leyendo #{ruta}: #{inspect(razon)}"}})
    end
  end

  defp procesar_lineas_ciudades([], acc, rechazos), do: {Enum.reverse(acc), rechazos}
  defp procesar_lineas_ciudades([linea | resto], acc, rechazos) do
    linea_limpia = String.trim(linea)

    if linea_limpia == "" do
      procesar_lineas_ciudades(resto, acc, rechazos)
    else
      partes = String.split(linea_limpia, "@")

      case partes do
        [id, nombre, hab_str] when id != "" and nombre != "" and hab_str != "" ->
          case Validador.parse_int(hab_str) do
            {:ok, hab} when hab > 0 ->
              ciudad = %Ciudad{id: id, nombre: nombre, habitantes: hab}
              procesar_lineas_ciudades(resto, [ciudad | acc], rechazos)

            _ ->
              procesar_lineas_ciudades(resto, acc, rechazos + 1)
          end

        _ ->
          procesar_lineas_ciudades(resto, acc, rechazos + 1)
      end
    end
  end

  def leer_movimientos(ruta, parent_pid) do
    case File.read(ruta) do
      {:ok, contenido} ->
        lineas = String.split(contenido, ["\r\n", "\n"], trim: false)
        {movimientos, rechazados} = procesar_lineas_movimientos(lineas, [], 0)
        send(parent_pid, {:movimientos, {:ok, movimientos, rechazados}})

      {:error, razon} ->
        send(parent_pid, {:movimientos, {:error, "Error leyendo #{ruta}: #{inspect(razon)}"}})
    end
  end

  defp procesar_lineas_movimientos([], acc, rechazos), do: {Enum.reverse(acc), rechazos}
  defp procesar_lineas_movimientos([linea | resto], acc, rechazos) do
    linea_limpia = String.trim(linea)

    if linea_limpia == "" do
      procesar_lineas_movimientos(resto, acc, rechazos)
    else
      partes = String.split(linea_limpia, "@")

      case partes do
        [cod, id_c, h_ini, h_fin, mag, prof]
        when cod != "" and id_c != "" and h_ini != "" and h_fin != "" and mag != "" and prof != "" ->
          with {:ok, hora_i} <- Validador.parse_hora(h_ini),
               {:ok, hora_f} <- Validador.parse_hora(h_fin),
               {:ok, magnitud} <- Validador.parse_float(mag),
               {:ok, profundidad} when profundidad >= 0.0 <- Validador.parse_float(prof) do
            mov = %Movimiento{
              codigo: cod,
              id_ciudad: id_c,
              hora_inicio: hora_i,
              hora_final: hora_f,
              magnitud: magnitud,
              profundidad: profundidad
            }
            procesar_lineas_movimientos(resto, [mov | acc], rechazos)
          else
            _ -> procesar_lineas_movimientos(resto, acc, rechazos + 1)
          end

        _ ->
          procesar_lineas_movimientos(resto, acc, rechazos + 1)
      end
    end
  end
end

defmodule Calculador do
  def filtrar_y_conciliar(movimientos, ciudades) do
    ids_ciudades = MapSet.new(Enum.map(ciudades, & &1.id))
    separar_validos(movimientos, ids_ciudades, [], 0)
  end

  defp separar_validos([], _ids, validos_acc, rechazos_acc) do
    {Enum.reverse(validos_acc), rechazos_acc}
  end

  defp separar_validos([mov | resto], ids, validos_acc, rechazos_acc) do
    if MapSet.member?(ids, mov.id_ciudad) do
      separar_validos(resto, ids, [mov | validos_acc], rechazos_acc)
    else
      separar_validos(resto, ids, validos_acc, rechazos_acc + 1)
    end
  end

  def calcular_estadisticas_ciudad(movimientos_ciudad) do
    recorrer_movimientos(movimientos_ciudad, 0, nil, 0.0)
  end

  
  defp recorrer_movimientos([], 0, nil, _suma_prof) do
    {:sin_movimientos, 0, "No aplica", "No aplica"}
  end

  defp recorrer_movimientos([], total, %Movimiento{codigo: c, magnitud: m}, suma_prof) do
    promedio = Float.round(suma_prof / total, 2)
    {:con_movimientos, total, "#{c} #{m}", "#{:erlang.float_to_binary(promedio, decimals: 2)} km"}
  end

  defp recorrer_movimientos([m | resto], 0, nil, _suma) do
    recorrer_movimientos(resto, 1, m, m.profundidad)
  end

  defp recorrer_movimientos([m | resto], total, max_actual, suma) do
    nuevo_max = if m.magnitud > max_actual.magnitud, do: m, else: max_actual
    recorrer_movimientos(resto, total + 1, nuevo_max, suma + m.profundidad)
  end
end

defmodule Reporte do
  def generar_texto(ciudades, movimientos, rech_ciudades, rech_movimientos) do
    {movs_validos, rech_id_invalido} = Calculador.filtrar_y_conciliar(movimientos, ciudades)
    total_rech_mov = rech_movimientos + rech_id_invalido

    lineas_ciudades =
      Enum.map(ciudades, fn ciudad ->
        movs = Enum.filter(movs_validos, &(&1.id_ciudad == ciudad.id))
        {estado, total, max_str, prom_str} = Calculador.calcular_estadisticas_ciudad(movs)

        detalle_movs =
          if estado == :sin_movimientos do
            "    Sin movimientos registrados\n"
          else
            Enum.map_join(movs, "\n", fn m ->
              "    - [#{m.codigo}] #{m.hora_inicio} -> #{m.hora_final} | Mag: #{m.magnitud} | Prof: #{m.profundidad} km"
            end) <> "\n"
          end

        """
        Ciudad: #{ciudad.nombre} (ID: #{ciudad.id})
        Habitantes: #{ciudad.habitantes}
        Movimientos:
        #{detalle_movs}    Total movimientos: #{total}
            Mayor magnitud: #{max_str}
            Profundidad promedio: #{prom_str}
        ------------------------------------------------------------
        """
      end)

    resumen_rechazados = """
    ============================================================
    REGISTROS RECHAZADOS:
      - Archivo ciudades.txt: #{rech_ciudades}
      - Archivo movimientos.txt: #{total_rech_mov}
    ============================================================
    """

    Enum.join(lineas_ciudades) <> resumen_rechazados
  end
end

defmodule Coordinador do
  def ejecutar(ruta_ciudades \\ "resources/ciudades.txt", ruta_movimientos \\ "resources/movimientos.txt") do
    parent = self()


    spawn(fn -> Lector.leer_ciudades(ruta_ciudades, parent) end)
    spawn(fn -> Lector.leer_movimientos(ruta_movimientos, parent) end)

    esperar_respuestas(nil, nil)
  end

  defp esperar_respuestas(res_c, res_m) when not is_nil(res_c) and not is_nil(res_m) do
    case {res_c, res_m} do
      {{:ok, ciudades, r_c}, {:ok, movimientos, r_m}} ->
        reporte = Reporte.generar_texto(ciudades, movimientos, r_c, r_m)
        IO.puts(reporte)

        case File.write("resources/reporte_sismos.txt", reporte) do
          :ok ->
            :ok
          {:error, razon} ->
            IO.puts(:stderr, "Error guardando el reporte: #{inspect(razon)}")
        end

      {{:error, msg}, _} ->
        IO.puts(:stderr, "Fallo en lectura: #{msg}")

      {_, {:error, msg}} ->
        IO.puts(:stderr, "Fallo en lectura: #{msg}")
    end
  end

  defp esperar_respuestas(res_c, res_m) do
    receive do
      {:ciudades, res} ->
        esperar_respuestas(res, res_m)

      {:movimientos, res} ->
        esperar_respuestas(res_c, res)
    end
  end
end

Coordinador.ejecutar()
