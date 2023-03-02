
 
------

select create_v_vm_cadastre()

  -----

 CREATE OR REPLACE FUNCTION create_v_vm_cadastre()
RETURNS INT AS $$
DECLARE
    r RECORD;
BEGIN



    FOR r IN SELECT schemaname, relname, kind, query, queryndex FROM dependances_v_vm_cadastre  --- selection du schéma indiqué dans l'argument de la fonction
    
    LOOP-- démarrage de la boucle de rafraichissement

        RAISE NOTICE 'CREATE %.%', r.schemaname, r.relname; ---- fait apparaitre un message indiquant le shéma et la VM en cours de raffraichissement
        EXECUTE 'DROP '|| r.kind || ' IF EXISTS '|| r.schemaname || '.' || r.relname || '; CREATE '|| r.kind ||' '|| r.schemaname || '.' || r.relname || ' as '|| r.query ||';'; --- execute le rafraichissement de la VM du schéma
        if r.queryndex is null 
		then RAISE NOTICE 'indexe null';
		else
		EXECUTE r.queryndex;
		end if;
    END LOOP;-- fin de la boucle de rafraichissement
 
    RETURN 1;
END 
$$ LANGUAGE plpgsql;