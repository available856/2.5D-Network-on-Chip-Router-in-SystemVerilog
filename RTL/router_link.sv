module router_link (
    router2router.upstream router_if_down,
    router2router.downstream router_if_up
);

    always_comb
    begin
        router_if_down.data = router_if_up.data;
        router_if_down.is_valid = router_if_up.is_valid;
        router_if_up.credits = router_if_down.credits;
        router_if_up.is_allocatable = router_if_down.is_allocatable;
    end

endmodule
