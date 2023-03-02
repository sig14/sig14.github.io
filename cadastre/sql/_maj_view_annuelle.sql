 drop table if exists public.dependances_v_vm_cadastre;
 create table  public.dependances_v_vm_cadastre as

  with a as 
                
                (WITH RECURSIVE s(start_schemaname, start_relname, start_relkind, relhasindex, schemaname, relname, relkind, reloid, owneroid, ownername, depth) AS (--recursive sur l'ensemble des données du schema cadastre 
                        SELECT n.nspname AS start_schemaname, -- nom du schema
                            c.relname AS start_relname, -- nom de la table
                            c.relkind AS start_relkind, 
                            c.relhasindex,
                            n2.nspname AS schemaname, -- nom du schema de la table dépendante
                            c2.relname, -- nom de la table dépendante
                            c2.relkind,
                            c2.oid AS reloid,
                            au.oid AS owneroid,
                            au.rolname AS ownername,
                            0 AS depth -- Commencer la dépendance à 0
                        FROM pg_class c
                            JOIN pg_namespace n ON c.relnamespace = n.oid AND (c.relkind = ANY (ARRAY['m', 'v','r','t','f', 'p'])) -- on commence par lister les tables, vues, vm dus chema cadastre
                            JOIN pg_depend d ON c.oid = d.refobjid
                            JOIN pg_rewrite r ON d.objid = r.oid
                            JOIN pg_class c2 ON r.ev_class = c2.oid
                            JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
                            JOIN pg_authid au ON au.oid = c2.relowner
                    where n.nspname = 'cadastre' -- on limite le schema d'origine au cadastre
                        UNION -- union pour la récursivité
                        SELECT s_1.start_schemaname,
                            s_1.start_relname,
                            s_1.start_relkind,
                            s_1.relhasindex,
                            n.nspname AS schemaname,
                            c2.relname,
                            c2.relkind,
                            c2.oid,
                            au.oid AS owneroid,
                            au.rolname AS ownername,
                            s_1.depth + 1 AS depth -- on ajoute 1 pour chaque dépendance trouvée
                        FROM s s_1
                            JOIN pg_depend d ON s_1.reloid = d.refobjid
                            JOIN pg_rewrite r ON d.objid = r.oid
                            JOIN pg_class c2 ON r.ev_class = c2.oid AND (c2.relkind = ANY (ARRAY['m'::"char", 'v'::"char"])) --- on limite les dependances aux vues et vues materialisées
                            JOIN pg_namespace n ON n.oid = c2.relnamespace
                            JOIN pg_authid au ON au.oid = c2.relowner
                        WHERE s_1.reloid <> c2.oid --- on joint les dépendance au niveau de l'oid
                        )
                SELECT -- lancement de la recursive
                    s.schemaname::varchar,
                    s.relname::varchar,
                    s.relkind,
                    sum(s.depth) as depth,
                    case when relkind = 'v' then 'VIEW' else 'MATERIALIZED VIEW' end as kind -- on précise les acronymes view et matview
                    FROM s
                        group by 
                    s.schemaname,
                    s.relname,
                    s.relkind,
                    s.depth
                    order by s.depth),

                z as (select a.*,
                case when a.relkind = 'm' then b.definition -- on ajoute les requêtes sql dans un champs
                ELSE c.view_definition end as query,
                i.indexdef as queryndex -- on ajoute les requêtes d'indexe dans un champs
                from a
                left join  pg_matviews b on b.schemaname = a.schemaname and b.matviewname = a.relname
                left join  information_schema.views c on c.table_schema = a.schemaname and c.table_name = a.relname
                left join  
                    pg_indexes i on a.schemaname = i.schemaname and i.tablename = a.relname 
                order by depth)
                
                
                select z.schemaname::varchar,
                    z.relname::varchar,
                    z.relkind,
                    z.kind,
                    sum(z.depth) as depth, --on somme les dépendances pour ordoner le futur rafraichissemnt en focntion du nume de dépendance
                    z.query, z.queryndex
                from z
                group by 
                    z.schemaname,
                    z.relname,
                    z.relkind,
                    z.kind,
                    z.query,
                z.queryndex
                order by depth;
                ;
