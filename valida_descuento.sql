DROP FUNCTION public.f_valida_descuento_actualizacion(int8);

CREATE OR REPLACE FUNCTION public.f_valida_descuentos(in_solicitud_id bigint)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$	
    declare    
	  LN_justificacion_id bigint;	   
	  LN_MODALIDAD character VARYING(20);
	  LN_DESCUENTO  float ;
	  LN_SQL character VARYING(500);
	 
	  LN_SQL1 character VARYING(500);
	  LN_SQL2 character VARYING(500);		
	  LN_SQL3 character VARYING(500);
	  LN_SQL4 character VARYING(500);
	 
	  LN_FECHA_SOLICITUD DATE;
	  LN_FECHA_APROBACION DATE;	   
	  rt record; 	
	  sql text;
	 
	  sql2 text;
	  LN_contador int:=0;	
	  LN_contadorV int:=0;	
	  LN_gr_interes_id bigint ;
	  LN_producto bigint;
      LN_validacion text;
      LN_resultado text;
      LN_SOLICITUD bigint := in_solicitud_id;
      LN_MONTO_OPERACION_PRODUCTO bigint;
      LN_MONTO_LIMITE bigint;
      LN_SIZE int;
   
	BEGIN		
		--Aqui se selecciona la solicitud y otros datos
		SELECT  DISTINCT  sc.MODALIDAD, DATE(sc.fecha_solicitud),DATE(sc.fecha_aprobacion)
		FROM SOLICITUD_CREDITO sc, JUSTIFICACION j 
		INTO LN_MODALIDAD, LN_FECHA_SOLICITUD, LN_FECHA_APROBACION
		WHERE sc.SOLICITUD_ID=j.SOLICITUD 
		AND sc.solicitud_id = in_solicitud_id;
	
		for rt in (	SELECT distinct dj.gr_interes_id, gr.producto_id as producto
					from 
					solicitud_credito sc --no es necesario guarda en variables pq ya se guardan en el loop
					inner join 
					justificacion j 
					on sc.solicitud_id = j.solicitud 
					inner join 
					detalle_justificacion dj 
					on j.justificacion_id = dj.justificacion_id
					inner join 
					grupo_restriccion gr 
					on gr.grupo_restriccion_id = dj.gr_interes_id 
					where sc.solicitud_id = LN_SOLICITUD
					and LN_FECHA_SOLICITUD between gr.valido_desde and gr.valido_hasta 
					and dj.grupo_restriccion_interes_id  IS NOT null)
			loop
				
			LN_gr_interes_id := rt.gr_interes_id;
	    	LN_producto := rt.producto ;
				
			--aqui se calcula el monto de la operacion por producto
			SELECT distinct  sum(dj.valor_operacion) 
			from 
			solicitud_credito sc into LN_MONTO_OPERACION_PRODUCTO
			inner join 
			justificacion j 
			on sc.solicitud_id = j.solicitud 
			inner join 
			detalle_justificacion dj 
			on j.justificacion_id = dj.justificacion_id
			inner join 
			grupo_restriccion gr 
			on gr.grupo_restriccion_id = dj.gr_interes_id 
			where sc.solicitud_id = LN_SOLICITUD 
			and j.estado in ('VERIFICADA','VALIDADA_DINARDAP')
			and LN_FECHA_SOLICITUD between gr.valido_desde and gr.valido_hasta 
			and dj.grupo_restriccion_interes_id  IS NOT null
			and gr.producto_id = LN_producto;
		
			if LN_MONTO_OPERACION_PRODUCTO is null then exit; end if; 
	 	
	        --se busca la sentencia sql que aplicara la condicion para el descuento
			SELECT grd.sentencia_sql, grd.descuento  
			FROM grupo_restriccion_descuento grd  INTO LN_SQL, LN_DESCUENTO 
			where grd.grupo_restriccion_id = LN_gr_interes_id
			and LN_FECHA_SOLICITUD
			between grd.valido_desde  and grd.valido_hasta ;

	        if LN_SQL is not null  then
	  			LN_contador := LN_contador + 1;
	  			RAISE NOTICE 'LN_gr_interes_id = % ', LN_gr_interes_id;
	  			RAISE NOTICE 'LN_producto = % ', LN_producto;
	  		
	  			--busco el valor del limite del monto maximo de los detalle justificacion
				select coalesce (r.maximo,0) 
				from restriccion r into LN_MONTO_LIMITE
				where r.grupo_restriccion_id = LN_gr_interes_id
				and r.tiempo_ejecucion ='REGLAS' and r.nombre_regla like '%MONTO%';
				
				if LN_MONTO_LIMITE is null then LN_MONTO_LIMITE:=0; end if;
			
				RAISE NOTICE 'LN_MONTO_LIMITE = % ', LN_MONTO_LIMITE;
			
				select length(LN_SQL) into LN_SIZE;
			
				
			
				RAISE NOTICE 'size = % ', LN_SIZE;
			
				if LN_SIZE >110 then 
			
					select substring(LN_SQL,1,83) into ln_sql1;
					select substring(LN_SQL,85,47) into ln_sql2;
					select substring(LN_SQL,133,61) into ln_sql3;
					select substring(LN_SQL,195,6) into ln_sql4;
				
	  				sql := 'select cast (case when '||ln_sql1||''||LN_MONTO_OPERACION_PRODUCTO||''||ln_sql2||''||LN_MONTO_LIMITE||''||ln_sql3||''||LN_MONTO_OPERACION_PRODUCTO||''||ln_sql4||' 
			 			then ''APLICA_DESCUENTO'' else ''SIN_DESCUENTO'' end as varchar),j.justificacion_id
						from 
						solicitud_credito sc 
						inner join 
						justificacion j 
						on sc.solicitud_id = j.solicitud 
						inner join 
						detalle_justificacion dj 
						on j.justificacion_id = dj.justificacion_id
						inner join 
						grupo_restriccion gr 
						on gr.grupo_restriccion_id = dj.gr_interes_id
						where sc.solicitud_id = '||LN_SOLICITUD||' 
						and dj.gr_interes_id = '||LN_gr_interes_id||'
						and j.estado in (''VERIFICADA'',''VALIDADA_DINARDAP'')
						and date('''||LN_FECHA_SOLICITUD||''')
						between gr.valido_desde and gr.valido_hasta 
						and dj.grupo_restriccion_interes_id  IS NOT null 
						group by j.justificacion_id';
					
					RAISE NOTICE 'sql = % ', sql;
				else
				
					select substring(LN_SQL,1,78) into ln_sql1;
					select substring(LN_SQL,80,6) into ln_sql2;
				
			
	  				sql := 'select cast (case when ('||ln_sql1||''||LN_MONTO_OPERACION_PRODUCTO||''||ln_sql2||') 
			 			then ''APLICA_DESCUENTO'' else ''SIN_DESCUENTO'' end as varchar),j.justificacion_id
						from 
						solicitud_credito sc 
						inner join 
						justificacion j 
						on sc.solicitud_id = j.solicitud 
						inner join 
						detalle_justificacion dj 
						on j.justificacion_id = dj.justificacion_id
						inner join 
						grupo_restriccion gr 
						on gr.grupo_restriccion_id = dj.gr_interes_id
						where sc.solicitud_id = '||LN_SOLICITUD||' 
						and dj.gr_interes_id = '||LN_gr_interes_id||'
						and j.estado in (''VERIFICADA'',''VALIDADA_DINARDAP'')
						and date('''||LN_FECHA_SOLICITUD||''')
						between gr.valido_desde and gr.valido_hasta 
						and dj.grupo_restriccion_interes_id  IS NOT null
						group by j.justificacion_id';
					RAISE NOTICE 'sql = % ', sql;
				end if;
                       
			    execute sql into LN_validacion,LN_justificacion_id;
			   	RAISE NOTICE 'justificacion = % ', LN_justificacion_id;
			    if LN_validacion = 'APLICA_DESCUENTO' then
			   		INSERT INTO solicitud_descuento (solicitud_id, grupo_restriccion_id , descuento , justificacion_id, producto_id,fecha_registro )
 			        VALUES(LN_SOLICITUD, LN_gr_interes_id, LN_DESCUENTO , LN_justificacion_id, LN_producto, NOW() );				  
 			        LN_contadorV := LN_contadorV + 1; 
			    end if;
			end if;
		
	    end loop ;	
	    return ' catnidad = ' ||LN_contador||'-> applica  = '||LN_contadorV ;
    END;
$function$
;