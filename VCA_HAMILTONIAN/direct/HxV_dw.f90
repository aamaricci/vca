  do jup=1,DimUp
     do jdw=1,DimDw
        mdw  = Hs(2)%map(jdw)
        ibdw  = bdecomp(mdw,Ns)
        j    = jup + (jdw-1)*dimUp
        !
        !
        !> H_imp: Off-diagonal elements, i.e. non-local part. 
        !remark: iorb=jorb cant have simultaneously n=0 and n=1 (Jcondition)
         do ilat=1,Nlat
             do jlat=1,Nlat
                 do iorb=1,Norb
                    do jorb=1,Norb
                       is = imp_state_index(ilat,iorb)
                       js = imp_state_index(jlat,jorb)
                       Jcondition = (impHloc(ilat,jlat,Nspin,Nspin,iorb,jorb)/=0d0).AND.(ibdw(js)==1).AND.(ibdw(is)==0)
                       if (Jcondition) then
                         call c(js,mdw,k1,sg1)
                         call cdg(is,k1,k2,sg2)
                         idw = binary_search(Hs(2)%map,k2)
                         i   = jup + (idw-1)*DimUp
                         htmp = impHloc(ilat,jlat,Nspin,Nspin,iorb,jorb)*sg1*sg2
                         !
                         Hv(i) = Hv(i) + htmp*vin(j)
                         !
                       endif
                    enddo
                enddo
            enddo
          enddo

        !
        !
        !>H_hyb: hopping terms for a given spin (imp <--> bath)
        if(Nbath>0)then
          do ilat=1,Nlat
            do iorb=1,Norb
               do kp=1,Nbath
                  ialfa=getBathStride(ilat,iorb,kp)
                  is = imp_state_index(ilat,iorb)
                  if( (diag_hybr(ilat,Nspin,iorb,kp)/=0d0) .AND. &
                       (ibdw(is)==1) .AND. (ibdw(ialfa)==0) )then
                     call c(is,mdw,k1,sg1)
                     call cdg(ialfa,k1,k2,sg2)
                     idw = binary_search(Hs(2)%map,k2)
                     i   = jup + (idw-1)*DimUp
                     htmp=diag_hybr(ilat,Nspin,iorb,kp)*sg1*sg2
                     !
                     Hv(i) = Hv(i) + htmp*vin(j)
                    !
                  endif
                  if( (diag_hybr(ilat,Nspin,iorb,kp)/=0d0) .AND. &
                       (ibdw(is)==0) .AND. (ibdw(ialfa)==1) )then
                     call c(ialfa,mdw,k1,sg1)
                     call cdg(is,k1,k2,sg2)
                     idw = binary_search(Hs(2)%map,k2)
                     i   = jup + (idw-1)*DimUp
                     htmp=diag_hybr(ilat,Nspin,iorb,kp)*sg1*sg2
                     !
                     Hv(i) = Hv(i) + htmp*vin(j)
                     !
                  endif
               enddo
            enddo
          enddo
        endif
        !
     end do
  enddo
